# Developer-only collector. Never starts a reference, companion or game.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$InputManifestPath,
    [ValidateSet('Intake', 'Lock', 'Verify', 'Materialize')][string]$Mode = 'Intake',
    [string]$LockPath,
    [string]$MaterializePath,
    [switch]$AllowMaterialization
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$categories = @('config', 'native', 'model', 'catalog', 'build', 'archive', 'adapter', 'instrumentation', 'packages', 'maps')
$excluded = @('.git', 'build', 'bin', 'obj', '.dart_tool', '.pub-cache', '.qualification', 'node_modules', 'cache', 'caches', 'logs', 'log', 'settings', 'credentials', 'secrets', 'appdata', '.vs', '.idea')

function Test-ExactText($Left, $Right) {
    return [string]::Equals($Left, $Right, [StringComparison]::Ordinal)
}
function Test-ExactMember($Values, [string]$Value) {
    foreach ($candidate in $Values) {
        if (Test-ExactText $candidate $Value) { return $true }
    }
    return $false
}
function Assert-RelativePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Contains('\') -or $Path.Contains(':') -or $Path.StartsWith('/')) {
        throw 'Include paths must be portable, explicit relative paths.'
    }
    foreach ($part in $Path.Split('/')) {
        if ($part -in @('', '.', '..') -or $part.ToLowerInvariant() -in $excluded) { throw "Excluded or traversing input path: $Path" }
    }
    if ($Path -match '(?i)(^|/)(\.env(\..*)?|.*\.(log|pfx|p12|key)|credentials\..*|secrets\..*|user\.config|.*\.csproj\.user)$') {
        throw "Excluded private input path: $Path"
    }
}

function Assert-NoLinks([string]$Root, [string]$Relative, [bool]$FileRequired = $true) {
    Assert-RelativePath $Relative
    $current = $Root
    foreach ($part in $Relative.Split('/')) {
        $current = [IO.Path]::Combine($current, $part)
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Linked input is forbidden: $Relative" }
    }
    if ($FileRequired -and $item.PSIsContainer) { throw "Input list must contain files, not directories: $Relative" }
    if (-not $FileRequired -and -not $item.PSIsContainer) { throw "Submodule root must be a directory: $Relative" }
    return $current
}

function Assert-NoLinkedOutput([string]$Path) {
    $current = $Path
    while (-not [string]::IsNullOrEmpty($current)) {
        $item = $null
        try {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        } catch [System.Management.Automation.ItemNotFoundException] {
            # Missing output components are allowed; existing ancestry is not skipped.
        }
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Output ancestry contains a link.'
        }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Resolve-ManifestPath([string]$Path, $Visited = $null) {
    $full = [IO.Path]::GetFullPath($Path)
    if ($null -eq $Visited) { $Visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase) }
    if (-not $Visited.Add($full)) { throw 'Input manifest link resolution contains a cycle.' }
    try {
        $root = [IO.Path]::GetPathRoot($full)
        $current = $root
        foreach ($part in $full.Substring($root.Length).Split([char[]]@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries)) {
            $item = Get-Item -LiteralPath ([IO.Path]::Combine($current, $part)) -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                $targets = @($item.Target)
                if ($targets.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$targets[0])) { throw 'Input manifest link target cannot be resolved.' }
                $target = [string]$targets[0]
                if (-not [IO.Path]::IsPathRooted($target)) { $target = [IO.Path]::Combine($current, $target) }
                $current = Resolve-ManifestPath $target $Visited
            } else {
                $current = $item.FullName
            }
        }
        return $current
    } finally {
        $Visited.Remove($full) | Out-Null
    }
}

function Read-Json([string]$Path) {
    return Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
}

function Write-Json([string]$Path, $Value) {
    Assert-NoLinkedOutput $Path
    $parent = [IO.Path]::GetDirectoryName($Path)
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $json = ConvertTo-Json -InputObject $Value -Depth 100
    $temporary = Join-Path $parent ('.tmp-' + [guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($temporary, $json + "`n", [Text.UTF8Encoding]::new($false))
        Assert-NoLinkedOutput $Path
        # Replace the directory entry instead of truncating a hardlinked source.
        if ([IO.File]::Exists($Path)) {
            [IO.File]::Replace($temporary, $Path, [NullString]::Value)
        } else {
            [IO.File]::Move($temporary, $Path)
        }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Get-FileFact([string]$Root, [Collections.IDictionary]$Entry) {
    $path = Assert-NoLinks $Root ([string]$Entry.path)
    if ([string]::IsNullOrWhiteSpace([string]$Entry.role)) { throw 'Every include needs a role.' }
    return [ordered]@{
        path = [string]$Entry.path
        sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        size_bytes = (Get-Item -LiteralPath $path).Length
        role = [string]$Entry.role
    }
}

function Invoke-Git([string]$Root, [string[]]$Arguments) {
    $lines = @(& git -C $Root @Arguments 2>$null)
    return @{ code = $LASTEXITCODE; lines = $lines }
}

function Get-Revision([string]$Root, [string[]]$Paths) {
    $head = Invoke-Git $Root @('rev-parse', '--verify', 'HEAD')
    $record = [ordered]@{ commit = $null; dirty = $null; closure_status = @() }
    if ($head.code -eq 0) {
        $record.commit = [string]$head.lines[0]
    } else {
        $record.commit_reason = 'No readable committed Git HEAD; intake only.'
    }
    $dirty = Invoke-Git $Root @('status', '--porcelain=v1', '--untracked-files=all')
    if ($dirty.code -eq 0) {
        $record.dirty = $dirty.lines.Count -gt 0
    } else {
        $record.dirty_reason = 'Git working-tree status is unavailable.'
    }
    # Read only the named closure status. Global dirty paths are never retained.
    if ($Paths.Count -gt 0) {
        $arguments = @('-c', 'core.quotePath=false', 'status', '--porcelain=v1', '--untracked-files=all', '--no-renames', '--') + @($Paths | ForEach-Object { ":(literal)$_" })
        $status = Invoke-Git $Root $arguments
        if ($status.code -eq 0) {
            $rows = @()
            foreach ($line in $status.lines) {
                if ($line.Length -lt 4) { throw 'Unexpected Git status record.' }
                $path = $line.Substring(3)
                # Git quotes whitespace/control-character names. Such names cannot be
                # interpreted ambiguously as a different portable payload path.
                if ($path.StartsWith('"')) { throw 'Quoted/control-character Git paths are not supported in the declared closure.' }
                Assert-RelativePath $path
                $rows += [ordered]@{ path = $path; status = $line.Substring(0, 2) }
            }
            $record.closure_status = $rows
        }
    }
    return $record
}

function Assert-Integrity([string]$Root, $Record) {
    foreach ($entry in $Record.files) {
        $fact = Get-FileFact $Root $entry
        if (-not (Test-ExactText $fact.sha256 $entry.sha256) -or $fact.size_bytes -ne $entry.size_bytes) {
            throw "Integrity drift invalidates the run: $($entry.path)"
        }
    }
}

function Assert-RevisionIntegrity([string]$Root, $Record) {
    $closurePaths = [string[]]@($Record.files | ForEach-Object { [string]$_.path })
    $current = Get-Revision $Root $closurePaths
    Assert-SameRevision $Record.reference $current
    foreach ($module in $Record.submodules) {
        $moduleRoot = Assert-NoLinks $Root ([string]$module.path) $false
        $modulePaths = [string[]]@($closurePaths | Where-Object { $_.StartsWith("$($module.path)/", [StringComparison]::Ordinal) } | ForEach-Object { $_.Substring($module.path.Length + 1) })
        Assert-SameRevision $module (Get-Revision $moduleRoot $modulePaths)
    }
}

function Assert-SameRevision($Expected, $Actual) {
    if (-not (Test-ExactText $Expected.commit $Actual.commit) -or $Expected.dirty -ne $Actual.dirty -or
        @($Expected.closure_status).Count -ne @($Actual.closure_status).Count) { throw 'Git revision/dirty facts drift invalidates the run.' }
    for ($index = 0; $index -lt @($Expected.closure_status).Count; $index++) {
        if (-not (Test-ExactText $Expected.closure_status[$index].path $Actual.closure_status[$index].path) -or
            -not (Test-ExactText $Expected.closure_status[$index].status $Actual.closure_status[$index].status)) { throw 'Git closure status drift invalidates the run.' }
    }
}

function Assert-Clearance($Record) {
    if (-not $Record.Contains('permission')) { throw 'No reviewed private_reference permission.' }
    $permission = $Record.permission
    if (-not (Test-ExactText $permission.use 'private_reference') -or -not (Test-ExactText $permission.status 'cleared') -or
        [string]::IsNullOrWhiteSpace([string]$permission.reviewer) -or
        [string]::IsNullOrWhiteSpace([string]$permission.reviewed_at) -or
        @($permission.evidence_ids).Count -eq 0) { throw 'Reviewed private_reference clearance is required.' }
    foreach ($entry in $Record.files) {
        if (-not (Test-ExactMember $permission.scope_paths $entry.path)) { throw "Permission does not cover $($entry.path)" }
    }
}

function Invoke-Contracts([string[]]$Arguments) {
    $cli = Join-Path $PSScriptRoot 'm0.dart'
    & dart run $cli @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'Qualification contract validation failed.' }
}

$source = [IO.Path]::GetFullPath($SourceRoot)
$rootItem = Get-Item -LiteralPath $source -Force
if (-not $rootItem.PSIsContainer -or ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'SourceRoot must be a real directory, not a link.' }
# Reject reparse points in root ancestry, not merely named children.
$ancestor = $rootItem
while ($null -ne $ancestor) {
    if (($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'SourceRoot ancestry contains a link.' }
    $ancestor = $ancestor.Parent
}
$output = [IO.Path]::GetFullPath($OutputPath)
$sourcePrefix = $source.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
if ($output.Equals($source, [StringComparison]::OrdinalIgnoreCase) -or $output.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'OutputPath must be outside the source tree.' }
Assert-NoLinkedOutput $output
Assert-NoLinkedOutput ($output + '.local.json')
$inputManifest = [IO.Path]::GetFullPath($InputManifestPath)
if ($Mode -ne 'Verify') {
    $inputManifest = Resolve-ManifestPath $inputManifest
    foreach ($collectorOutput in @($output, ($output + '.local.json'))) {
        if ($collectorOutput.Equals($inputManifest, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Collector outputs must be distinct from the input manifest.'
        }
    }
}
$manifest = Read-Json $inputManifest
if ($manifest.schema_version -ne 1 -or [string]::IsNullOrWhiteSpace([string]$manifest.id) -or -not $manifest.ContainsKey('files')) { throw 'Input manifest requires schema_version 1, id and explicit files array.' }
$entries = @($manifest.files)
$paths = [string[]]@($entries | ForEach-Object { [string]$_.path })
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($path in $paths) {
    Assert-RelativePath $path
    if (-not $seen.Add($path)) { throw "Duplicate/case-aliased include path: $path" }
}
[Array]::Sort($paths, [StringComparer]::Ordinal)
$byPath = @{}
foreach ($entry in $entries) { $byPath[[string]$entry.path] = $entry }

if ($Mode -eq 'Verify') {
    if ([string]::IsNullOrWhiteSpace($LockPath)) { throw 'Verify requires -LockPath.' }
    Invoke-Contracts @('validate', $LockPath)
    $record = Read-Json $LockPath
    if ($record.record_type -notin @('source_intake', 'source_lock')) { throw 'Verify requires a source record.' }
    if ($paths.Count -ne @($record.files).Count) { throw 'Input manifest closure differs from recorded closure.' }
    foreach ($file in $record.files) { if (-not $seen.Contains($file.path)) { throw 'Input manifest closure differs from recorded closure.' } }
    Assert-Integrity $source $record
    Assert-RevisionIntegrity $source $record
    Invoke-Contracts @('validate', $LockPath, '--source-root', $source)
    Write-Output 'Integrity verified for the exact declared closure; no reference was invoked.'
    return
}

if ($Mode -ne 'Materialize' -and ($AllowMaterialization -or -not [string]::IsNullOrWhiteSpace($MaterializePath))) { throw 'Copying options are only permitted in explicit Materialize mode.' }
$facts = @($paths | ForEach-Object { Get-FileFact $source $byPath[$_] })
$factByPath = @{}
foreach ($fact in $facts) { $factByPath[$fact.path] = $fact }
$effective = [ordered]@{}
foreach ($category in $categories) {
    if (-not $manifest.ContainsKey('effective_inputs') -or -not $manifest.effective_inputs.ContainsKey($category) -or $null -eq $manifest.effective_inputs[$category]) {
        $effective[$category] = $null
        $reasonKey = "${category}_reason"
        $reason = if ($manifest.ContainsKey('effective_inputs') -and $manifest.effective_inputs.ContainsKey($reasonKey)) { $manifest.effective_inputs[$reasonKey] } else { 'Identity is not declared; final reproducibility remains unverified.' }
        $effective[$reasonKey] = $reason
        continue
    }
    $rows = @()
    foreach ($input in $manifest.effective_inputs[$category]) {
        $row = @{} + $input
        if ($row.ContainsKey('path')) {
            if (-not $factByPath.ContainsKey([string]$row.path)) { throw "Effective $category path is outside the explicit closure." }
            $actualHash = $factByPath[[string]$row.path].sha256
            if ($row.ContainsKey('sha256') -and -not (Test-ExactText $row.sha256 $actualHash)) { throw "Declared $category hash differs from source bytes." }
            $row.sha256 = $actualHash
        }
        $rows += $row
    }
    $effective[$category] = $rows
}
$submodules = @()
if ($manifest.ContainsKey('submodules')) {
    $subSeen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($relative in $manifest.submodules) {
        if (-not $subSeen.Add([string]$relative)) { throw 'Duplicate submodule root.' }
        $moduleRoot = Assert-NoLinks $source ([string]$relative) $false
        $modulePaths = [string[]]@($paths | Where-Object { $_.StartsWith("$relative/", [StringComparison]::Ordinal) } | ForEach-Object { $_.Substring($relative.Length + 1) })
        $revision = Get-Revision $moduleRoot $modulePaths
        $revision.path = $relative
        $submodules += $revision
    }
}
$record = [ordered]@{
    schema_version = 1
    record_type = if ($Mode -eq 'Intake') { 'source_intake' } else { 'source_lock' }
    id = [string]$manifest.id
    collected_at = [DateTime]::UtcNow.ToString('O')
    reference = Get-Revision $source $paths
    submodules = $submodules
    files = $facts
    effective_inputs = $effective
    closure_complete = $manifest.ContainsKey('closure_complete') -and $manifest.closure_complete -eq $true
    closure_declaration = if ($manifest.ContainsKey('closure_declaration')) { $manifest.closure_declaration } else { 'Explicit metadata intake only; complete effective closure has not been established.' }
    freeze_id = $null
}
if ($manifest.ContainsKey('permission')) { $record.permission = $manifest.permission }
if ($Mode -eq 'Intake') {
    $record.freeze_id_reason = 'Metadata-only intake is not a permission-cleared, reproducible final source lock.'
} else {
    if ($record.closure_complete -ne $true) { throw 'Final locks require an explicit complete closure declaration.' }
    Assert-Clearance $record
    # Compute the identity with the same canonicalizer consumers use. No native/reference invocation.
    # A failed pre/post check must not leave a purported final lock at OutputPath.
    $pending = [IO.Path]::GetTempFileName()
    try {
        Write-Json $pending $record
        Invoke-Contracts @('hash-lock', $pending, '--write')
        $record = Read-Json $pending
        Invoke-Contracts @('validate', $pending)
    } finally {
        [IO.File]::Delete($pending)
    }
}

# Every operation rehashes the source after collection; changed bytes never produce successful evidence.
Assert-Integrity $source $record
Assert-RevisionIntegrity $source $record
if ($Mode -eq 'Materialize') {
    if (-not $AllowMaterialization -or [string]::IsNullOrWhiteSpace($MaterializePath)) { throw 'Materialize requires -AllowMaterialization and -MaterializePath.' }
    Assert-Clearance $record
    $target = [IO.Path]::GetFullPath($MaterializePath)
    if ($target.Equals($source, [StringComparison]::OrdinalIgnoreCase) -or $target.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Materialization must be outside the source tree.' }
    $targetPrefix = $target.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    foreach ($collectorOutput in @($output, ($output + '.local.json'))) {
        if ($collectorOutput.Equals($target, [StringComparison]::OrdinalIgnoreCase) -or $collectorOutput.StartsWith($targetPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Collector outputs must be outside the materialization tree.'
        }
    }
    if (Test-Path -LiteralPath $target) { throw 'Materialization target must not already exist; nothing is overwritten.' }
    $parentPath = [IO.Path]::GetDirectoryName($target)
    while (-not (Test-Path -LiteralPath $parentPath)) {
        $parentPath = [IO.Path]::GetDirectoryName($parentPath)
    }
    $parent = Get-Item -LiteralPath $parentPath -Force
    while ($null -ne $parent) {
        if (($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Materialization ancestry contains a link.' }
        $parent = $parent.Parent
    }
    Assert-Integrity $source $record
    [IO.Directory]::CreateDirectory($target) | Out-Null
    foreach ($file in $record.files) {
        $from = Assert-NoLinks $source $file.path
        $to = [IO.Path]::Combine($target, $file.path.Replace('/', [IO.Path]::DirectorySeparatorChar))
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to)) | Out-Null
        [IO.File]::Copy($from, $to, $false)
    }
    Assert-Integrity $source $record
    Assert-RevisionIntegrity $source $record
    Assert-Integrity $target $record
}
Write-Json $output $record
Invoke-Contracts @('validate', $output)
# Private local locators are deliberately separate from the portable JSON payload.
$local = [ordered]@{ source_root = $source; input_manifest_path = $inputManifest }
if ($Mode -eq 'Materialize') { $local.materialized_root = $target }
Write-Json ($output + '.local.json') $local
Write-Output "$($record.record_type) written; only explicit declared files were hashed."
