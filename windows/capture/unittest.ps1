# Builds and runs the native capture unit test in the Flutter CMake tree
# (run `flutter build windows --release` once first). Unlike selftest.ps1 it
# has no game gate: the unit test uses injected environments and fakes only and
# opens no real window, hook, hotkey or capture.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$buildDir = Join-Path $root 'build/windows/x64'
$cache = Join-Path $buildDir 'CMakeCache.txt'
if (-not (Test-Path $cache)) { throw 'build/windows/x64 is missing; run flutter build windows --release first' }
$cmake = (Select-String -Path $cache -Pattern '^CMAKE_COMMAND:INTERNAL=(.*)$').Matches[0].Groups[1].Value
& $cmake --build $buildDir --config Release --target blackgrid_capture_unittest
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $buildDir 'capture/Release/blackgrid_capture_unittest.exe')
exit $LASTEXITCODE
