#Requires -Version 5.1
<#
.SYNOPSIS
    Builds VVV for Windows (x86 and/or x64) and stages a self-contained run folder.

.DESCRIPTION
    Expects the dependency tree next to this script (or one directory above it):

        deps\wxWidgets-3.2.8-x86
        deps\wxWidgets-3.2.8-x64
        deps\taglib-install-x86
        deps\taglib-install-x64
        deps\firebird-5.0.4-x86
        deps\firebird-5.0.4-x64

    Output:
        build-<arch>\src\Release\vvv.exe
        run-<arch>\                          (app + wxWidgets + Firebird 5 + data files)

.PARAMETER Arch
    x64 (default). 32-bit builds were dropped with VVV 2.0.

.PARAMETER Config
    Release (default) or Debug.

.PARAMETER NoStage
    Only build; do not create the run-<arch> folder.

.EXAMPLE
    .\build.ps1
#>
[CmdletBinding()]
param(
    [ValidateSet('x64')]
    [string]$Arch = 'x64',

    [ValidateSet('Release', 'Debug')]
    [string]$Config = 'Release',

    [switch]$NoStage
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

# The sources are the repository content itself; the script may also live one
# level above the checkout (as in a scratch workspace).
$SourceDir = if (Test-Path (Join-Path $Root 'CMakeLists.txt')) { $Root }
             else { Join-Path $Root 'VVV-src' }

# Dependencies live in the source tree; accept one level above for convenience.
$DepsDir = if (Test-Path (Join-Path $Root 'deps')) { Join-Path $Root 'deps' }
           else { Join-Path $Root '..\deps' }

function Find-CMake {
    $candidates = @(
        (Get-Command cmake.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source),
        'C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe',
        'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe',
        'C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe',
        'C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
    ) | Where-Object { $_ -and (Test-Path $_) }

    if (-not $candidates) {
        throw 'cmake.exe not found. Install Visual Studio Build Tools with the C++ CMake tools component.'
    }
    return @($candidates)[0]
}

function Get-VsGenerator {
    # Pick the newest installed Visual Studio generator CMake knows about.
    $cmake = $script:CMake
    $help = & $cmake --help 2>&1 | Out-String
    foreach ($name in @('Visual Studio 18 2026', 'Visual Studio 17 2022')) {
        if ($help -match [regex]::Escape($name)) { return $name }
    }
    throw "No supported Visual Studio generator found. CMake generators:`n$help"
}

$script:CMake = Find-CMake
$Generator = Get-VsGenerator
Write-Host "CMake:     $script:CMake"
Write-Host "Generator: $Generator"

$Architectures = if ($Arch -eq 'all') { @('x86', 'x64') } else { @($Arch) }

function Invoke-Build([string]$a) {
    $wxArch = if ($a -eq 'x86') { 'x86' } else { 'x64' }
    $wxLibSub = if ($a -eq 'x86') { 'vc14x_dll' } else { 'vc14x_x64_dll' }
    $wxRoot = Join-Path $DepsDir "wxWidgets-3.2.8-$wxArch"
    $wxLibDir = Join-Path $wxRoot "lib\$wxLibSub"
    $taglibRoot = Join-Path $DepsDir "taglib-install-$a"
    $taglibLib = Join-Path $taglibRoot 'lib\tag.lib'
    $fbRoot = Join-Path $DepsDir "firebird-5.0.4-$a"
    $buildDir = Join-Path $Root "build-$a"
    $runDir = Join-Path $Root "run-$a"
    $vsArch = if ($a -eq 'x86') { 'Win32' } else { 'x64' }

    foreach ($p in @($wxRoot, $wxLibDir, $taglibRoot, $taglibLib, $fbRoot)) {
        if (-not (Test-Path $p)) { throw "Missing dependency for ${a}: $p" }
    }

    Write-Host ""
    Write-Host "=== Configure $a ($Config) ===" -ForegroundColor Cyan
    & $script:CMake -S $SourceDir -B $buildDir -G $Generator -A $vsArch `
        -DwxWidgets_ROOT_DIR="$wxRoot" `
        -DwxWidgets_LIB_DIR="$wxLibDir" `
        -DwxWidgets_CONFIGURATION=mswu `
        -DwxWidgets_USE_REL_AND_DBG=OFF `
        -DTAGLIB_INCLUDE_PATH="$(Join-Path $taglibRoot 'include\taglib')" `
        -DTAGLIB_LIB_PATH_DEBUG="$taglibLib" `
        -DTAGLIB_LIB_PATH_RELEASE="$taglibLib" `
        -DVVV_FIREBIRD_ROOT="$fbRoot" `
        -DCMAKE_CXX_STANDARD=17
    if ($LASTEXITCODE -ne 0) { throw "CMake configure failed for $a" }

    Write-Host ""
    Write-Host "=== Build $a ($Config) ===" -ForegroundColor Cyan
    & $script:CMake --build $buildDir --config $Config --parallel
    if ($LASTEXITCODE -ne 0) { throw "Build failed for $a" }

    if ($NoStage) { return }

    Write-Host ""
    Write-Host "=== Stage $runDir ===" -ForegroundColor Cyan
    if (Test-Path $runDir) { Remove-Item $runDir -Recurse -Force }
    & $script:CMake --install $buildDir --config $Config --prefix $runDir
    if ($LASTEXITCODE -ne 0) { throw "Install/stage failed for $a" }

    Write-Host "Staged: $runDir" -ForegroundColor Green
}

foreach ($a in $Architectures) { Invoke-Build $a }

Write-Host ""
Write-Host "Done." -ForegroundColor Green
