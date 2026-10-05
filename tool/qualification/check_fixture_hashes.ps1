# Developer-only, explicit-file verifier. Does not invoke a reference, refresh hashes,
# discover directories, or claim that synthetic vectors qualify native behavior.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$FixtureRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CanonicalJson($Value) {
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [System.Collections.IDictionary]) {
        [string[]]$keys = @($Value.Keys)
        [Array]::Sort($keys, [StringComparer]::Ordinal)
        $parts = foreach ($key in $keys) {
            (ConvertTo-Json -InputObject $key -Compress) + ':' + (Get-CanonicalJson $Value[$key])
        }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $parts = foreach ($item in $Value) { Get-CanonicalJson $item }
        return '[' + ($parts -join ',') + ']'
    }
    return ConvertTo-Json -InputObject $Value -Compress -Depth 100
}
function Get-TextHash([string]$Text) {
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant()
}
function Test-ExactText($Left, $Right) {
    return [string]::Equals($Left, $Right, [StringComparison]::Ordinal)
}
function Test-ExactMember($Values, [string]$Value) {
    foreach ($candidate in $Values) {
        if (Test-ExactText $candidate $Value) { return $true }
    }
    return $false
}
function Assert-Hash($Hash, [string]$Name) {
    if ($Hash -isnot [string] -or $Hash -cnotmatch '^[0-9a-f]{64}$') { throw "$Name must be lowercase SHA-256" }
}
function Get-SafePayload([string]$RelativePath) {
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or $RelativePath -match '[:\\]' -or
        $RelativePath.StartsWith('/') -or @($RelativePath.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0) {
        throw "Nonportable payload path: $RelativePath"
    }
    if ($RelativePath -notmatch '^(test/fixtures/m0/|docs/qualification/m0/)' -or $RelativePath -notmatch '\.json$') {
        throw "Payload is outside the declared qualification JSON scope: $RelativePath"
    }
    $current = $root
    foreach ($segment in $RelativePath.Split('/')) {
        $current = Join-Path $current $segment
        if (-not (Test-Path -LiteralPath $current)) { throw "Missing payload: $RelativePath" }
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Linked payload path: $RelativePath" }
    }
    if (-not (Test-Path -LiteralPath $current -PathType Leaf)) { throw "Payload is not a file: $RelativePath" }
    return $current
}
function Visit-Parent([string]$Id) {
    if ($visiting.Contains($Id)) { throw "Fixture parent cycle at $Id" }
    if ($visited.Contains($Id)) { return }
    [void]$visiting.Add($Id)
    foreach ($parent in $filesById[$Id].parent_ids) { Visit-Parent $parent }
    [void]$visiting.Remove($Id)
    [void]$visited.Add($Id)
}

try {
    $root = [IO.Path]::GetFullPath($FixtureRoot)
    $rootItem = Get-Item -LiteralPath $root -Force
    if (-not $rootItem.PSIsContainer) { throw 'FixtureRoot must be a directory' }
    $ancestor = $rootItem
    while ($null -ne $ancestor) {
        if (($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'FixtureRoot has a linked ancestor' }
        $ancestor = $ancestor.Parent
    }
    $manifestBytes = [IO.File]::ReadAllBytes([IO.Path]::GetFullPath($ManifestPath))
    $manifestSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($manifestBytes)).ToLowerInvariant()
    $manifest = [Text.Encoding]::UTF8.GetString($manifestBytes) | ConvertFrom-Json -AsHashtable -Depth 100
    if ($manifest.schema_version -ne 1 -or -not (Test-ExactText $manifest.record_type 'fixture_manifest')) { throw 'Expected a version-1 fixture manifest' }
    if (@($manifest.files).Count -eq 0) { throw 'Manifest must declare real JSON payload files' }
    $filesById = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $records = [Collections.Generic.List[object]]::new()
    $payloadCases = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    foreach ($file in $manifest.files) {
        if ([string]::IsNullOrWhiteSpace($file.id) -or $filesById.ContainsKey($file.id)) { throw 'Empty or duplicate file ID' }
        if (-not $paths.Add($file.path)) { throw 'Duplicate payload path' }
        Assert-Hash $file.sha256 'Payload hash'
        Assert-Hash $file.recipe_sha256 'Recipe hash'
        if (-not (Test-ExactText (Get-TextHash (Get-CanonicalJson $file.recipe)) $file.recipe_sha256)) { throw "Altered recipe: $($file.id)" }
        $path = Get-SafePayload $file.path
        $bytes = [IO.File]::ReadAllBytes($path)
        if ($bytes.LongLength -ne $file.size_bytes -or
            -not (Test-ExactText ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()) $file.sha256)) {
            throw "Payload byte drift: $($file.path)"
        }
        $record = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json -AsHashtable -Depth 100
        if ($record.schema_version -ne 1) { throw 'Unknown payload schema version' }
        $records.Add($record)
        if (Test-ExactText $record.record_type 'fixture_manifest') {
            foreach ($case in $record.cases) {
                $identity = Get-CanonicalJson $case
                if ($payloadCases.ContainsKey($case.id) -and -not (Test-ExactText $payloadCases[$case.id] $identity)) { throw "Conflicting case payloads: $($case.id)" }
                $payloadCases[$case.id] = $identity
            }
        }
        $filesById.Add($file.id, $file)
    }
    foreach ($file in $manifest.files) {
        if (@($file.parent_ids).Count -ne @($file.parent_bindings).Count) { throw 'Parent IDs and exact bindings disagree' }
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($binding in $file.parent_bindings) {
            if (-not $seen.Add($binding.id) -or -not (Test-ExactMember $file.parent_ids $binding.id) -or -not $filesById.ContainsKey($binding.id)) { throw 'Unknown or duplicate parent' }
            Assert-Hash $binding.sha256 'Parent binding hash'
            if (-not (Test-ExactText $binding.sha256 $filesById[$binding.id].sha256)) { throw 'Altered parent identity' }
        }
        if (@($file.parent_ids).Count -eq 0 -and -not (Test-ExactText $file.recipe.kind 'original_authorship')) { throw 'Original payload must declare original authorship' }
        if (@($file.parent_ids).Count -gt 0 -and -not (Test-ExactText $file.recipe.kind 'derived')) { throw 'Parented payload must declare an exact derived recipe' }
    }
    $visiting = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($id in $filesById.Keys) { Visit-Parent $id }
    $manifestIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($case in $manifest.cases) {
        if (-not $manifestIds.Add($case.id) -or -not $payloadCases.ContainsKey($case.id) -or
            -not (Test-ExactText (Get-CanonicalJson $case) $payloadCases[$case.id])) { throw "Unbound or altered embedded case: $($case.id)" }
        if ((Test-ExactText $case.data_class 'synthetic') -and -not (Test-ExactText $case.role 'expectation_only')) { throw 'Synthetic corpus is expectation-only, not a reference/native observation' }
    }
    if ($manifestIds.Count -ne $payloadCases.Count) { throw 'Payload and manifest case rosters disagree' }
    # Original/derived synthetic contracts are not screenshot masters, controls,
    # or acquired native evidence. This corpus intentionally has no such inputs.
    $coverage = [ordered]@{
        actual_master_cases = 0
        native_display_cells = 0
        independent_map_controls = 0
        synthetic_geometry_cells = 0
    }
    $geometry = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($case in $manifest.cases) {
        if (-not (Test-ExactText $case.role 'expectation_only') -or -not (Test-ExactText $case.data_class 'synthetic')) { throw 'This authored corpus checker accepts synthetic expectation-only cases; real inputs require separately reviewed intake' }
        if (Test-ExactMember $case.coverage_tags 'capture:16-cells') { [void]$geometry.Add($case.display_cell_id) }
    }
    $matrices = @($records | Where-Object { Test-ExactText $_.record_type 'display_matrix' })
    if ($matrices.Count -ne 1 -or @($matrices[0].cells).Count -ne 16) { throw 'Exactly one complete 16-cell matrix is required' }
    $combinations = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $expectedHeights = @{ '1920'=1080; '2560'=1440; '3440'=1440; '3840'=2160 }
    foreach ($cell in $matrices[0].cells) {
        $expectedId = "$($cell.width)-$($cell.os_scale_percent)"
        if ($cell.width -notin @(1920,2560,3440,3840) -or $cell.os_scale_percent -notin @(100,125,150,200) -or
            $cell.height -ne $expectedHeights[[string]$cell.width] -or
            -not (Test-ExactText $cell.id $expectedId) -or -not $combinations.Add($expectedId) -or -not $geometry.Contains($cell.id)) { throw 'Missing or invalid deterministic display cell' }
        if (-not (Test-ExactText $cell.evidence_class 'synthetic') -or @($cell.evidence_ids).Count -ne 0) { throw 'Geometry cannot establish native/image evidence' }
        foreach ($caseId in $cell.geometry_case_ids) { if (-not $manifestIds.Contains($caseId)) { throw 'Unknown geometry case' } }
    }
    $coverage.synthetic_geometry_cells = $geometry.Count
    $mapRecords = @($records | Where-Object { Test-ExactText $_.record_type 'map_controls' })
    if ($mapRecords.Count -ne 1 -or @($mapRecords[0].controls).Count -ne 0) { throw 'Real independent controls are not present in this synthetic corpus' }
    foreach ($key in $coverage.Keys) {
        if (-not $manifest.coverage_claims.Contains($key) -or $manifest.coverage_claims[$key] -ne $coverage[$key]) { throw "Unsupported coverage claim: $key" }
    }
    [ordered]@{ status='verified'; manifest_id=$manifest.id; manifest_sha256=$manifestSha256; payload_files=$filesById.Count; expectation_cases=$manifestIds.Count; coverage=$coverage; qualification='incomplete'; limitations='Byte/recipe linkage and synthetic roster only; no native/reference acquisition or reviewed independent map controls.' } | ConvertTo-Json -Depth 20 -Compress
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
