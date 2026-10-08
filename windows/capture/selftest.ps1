# Builds and runs the native capture self-test in the Flutter CMake tree
# (run `flutter build windows --release` once first). The self-test itself
# refuses to start unless BLACKGRID_NO_GAMES_RUNNING=1 confirms no game is
# running, and while a known game process is listed.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$buildDir = Join-Path $root 'build/windows/x64'
$cache = Join-Path $buildDir 'CMakeCache.txt'
if (-not (Test-Path $cache)) { throw 'build/windows/x64 is missing; run flutter build windows --release first' }
$cmake = (Select-String -Path $cache -Pattern '^CMAKE_COMMAND:INTERNAL=(.*)$').Matches[0].Groups[1].Value
& $cmake --build $buildDir --config Release --target blackgrid_capture_selftest
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $buildDir 'capture/Release/blackgrid_capture_selftest.exe')
exit $LASTEXITCODE
