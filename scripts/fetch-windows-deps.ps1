#Requires -Version 5.1
<#
.SYNOPSIS
    Provisions the Windows x64 build dependencies under deps\ from official
    downloads, so that build.ps1 can run from a fresh checkout.

.DESCRIPTION
    Downloads (into deps\downloads\, kept as a cache) and unpacks:

        wxWidgets 3.2.8  - prebuilt MSVC binaries from the wxWidgets GitHub
                           release (headers + vc14x_x64 Dev import libraries +
                           ReleaseDLL binaries) -> deps\wxWidgets-3.2.8-x64
        Firebird  5.0.4  - the official Windows zip kit (runtime files) ->
                           deps\firebird-5.0.4-x64
        TagLib    2.3.1  - source tarball, built as a static library with
                           CMake -> deps\taglib-install-x64

    Every step is skipped when its target directory already looks complete,
    so the script is safe to re-run. Run build.ps1 afterwards.

.PARAMETER DepsDir
    Directory that receives deps\... contents. Default: <repo root>\deps
    (the repo root is one level above this script). build.ps1 finds deps
    either next to itself or one level above, so both work.

.PARAMETER SkipWx
.PARAMETER SkipFirebird
.PARAMETER SkipTagLib
    Skip an individual dependency (useful to redo just one).

.EXAMPLE
    .\scripts\fetch-windows-deps.ps1
#>
[CmdletBinding()]
param(
    [string]$DepsDir,
    [switch]$SkipWx,
    [switch]$SkipFirebird,
    [switch]$SkipTagLib
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $DepsDir) { $DepsDir = Join-Path $RepoRoot 'deps' }

# --- versions and URLs ------------------------------------------------------
$WX_VERSION       = '3.2.8'
$WX_BASE          = "https://github.com/wxWidgets/wxWidgets/releases/download/v$WX_VERSION"
# SHA-1 checksums as published in the wxWidgets v3.2.8 release notes
$WX_ASSETS = @(
    @{ Name = "wxWidgets-$WX_VERSION-headers.7z";            Sha1 = '86a2c99b4e9608b7cfc0b59e0f5a6d200a9d2541' },
    @{ Name = "wxMSW-$WX_VERSION`_vc14x_x64_Dev.7z";         Sha1 = 'abf0be396b7648405883058090e4ad5f4d13918e' },
    @{ Name = "wxMSW-$WX_VERSION`_vc14x_x64_ReleaseDLL.7z";  Sha1 = '2ad8fcc7bf28db8126eae55284eccbdfa7d02e27' }
)

$FB_VERSION   = '5.0.4'
$FB_NAME      = 'Firebird-5.0.4.1812-0-windows-x64.zip'
$FB_URL       = "https://github.com/FirebirdSQL/firebird/releases/download/v$FB_VERSION/$FB_NAME"

$TL_VERSION   = '2.3.1'
$TL_NAME      = "taglib-$TL_VERSION.tar.gz"
$TL_URL       = "https://github.com/taglib/taglib/releases/download/v$TL_VERSION/$TL_NAME"
# SHA-256 digest published on the GitHub release asset
$TL_SHA256    = 'a19d90e6fd41d09a0281ec0fe762d51491d7a6ccffc923c4f7868c5e647ca230'

# --- helpers ----------------------------------------------------------------
function Find-SevenZip {
    $candidates = @(
        "$env:ProgramFiles\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
    ) | Where-Object { $_ -and (Test-Path $_) }
    if ($candidates) { return @($candidates)[0] }
    $cmd = Get-Command 7z.exe, 7za.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    throw '7z.exe not found. Install 7-Zip (or put 7z.exe on PATH).'
}

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
    param([string]$CMake)
    $help = & $CMake --help 2>&1 | Out-String
    foreach ($name in @('Visual Studio 18 2026', 'Visual Studio 17 2022')) {
        if ($help -match [regex]::Escape($name)) { return $name }
    }
    throw "No supported Visual Studio generator found."
}

function Get-RemoteFile {
    param(
        [string]$Url,
        [string]$File,
        [string]$Algorithm,   # 'SHA1' / 'SHA256' or $null for no check
        [string]$ExpectedHash
    )
    $needDownload = $true
    if (Test-Path $File) {
        if ($ExpectedHash) {
            $actual = (Get-FileHash $File -Algorithm $Algorithm).Hash.ToLowerInvariant()
            if ($actual -eq $ExpectedHash.ToLowerInvariant()) { $needDownload = $false }
            else { Write-Warning "${File}: cached file hash mismatch, re-downloading" }
        } else {
            $needDownload = $false
        }
    }
    if ($needDownload) {
        Write-Host "Downloading $Url"
        Invoke-WebRequest -Uri $Url -OutFile $File -UseBasicParsing
        if ($ExpectedHash) {
            $actual = (Get-FileHash $File -Algorithm $Algorithm).Hash.ToLowerInvariant()
            if ($actual -ne $ExpectedHash.ToLowerInvariant()) {
                Remove-Item $File -Force
                throw "$File has hash $actual, expected $ExpectedHash"
            }
        }
    } else {
        Write-Host "Cached: $File"
    }
    return $File
}

$7z = Find-SevenZip
$DownloadDir = Join-Path $DepsDir 'downloads'
New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
Write-Host "Deps target: $DepsDir"

# --- wxWidgets --------------------------------------------------------------
if (-not $SkipWx) {
    $wxTarget = Join-Path $DepsDir "wxWidgets-$WX_VERSION-x64"
    $wxMarker = Join-Path $wxTarget "lib\vc14x_x64_dll\wxbase32u.lib"
    if (Test-Path $wxMarker) {
        Write-Host "wxWidgets already present: $wxTarget"
    } else {
        foreach ($a in $WX_ASSETS) {
            $local = Join-Path $DownloadDir $a.Name
            Get-RemoteFile -Url "$WX_BASE/$($a.Name)" -File $local -Algorithm SHA1 -ExpectedHash $a.Sha1 | Out-Null
        }
        Write-Host "Extracting wxWidgets into $wxTarget"
        New-Item -ItemType Directory -Force -Path $wxTarget | Out-Null
        foreach ($a in $WX_ASSETS) {
            & $7z x "-o$wxTarget" (Join-Path $DownloadDir $a.Name) -y | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "7z failed on $($a.Name)" }
        }
        if (-not (Test-Path $wxMarker)) { throw "wxWidgets extraction did not produce the expected layout under $wxTarget" }
    }
} else { Write-Host 'wxWidgets: skipped (-SkipWx)' }

# --- Firebird ---------------------------------------------------------------
if (-not $SkipFirebird) {
    $fbTarget = Join-Path $DepsDir "firebird-$FB_VERSION-x64"
    $fbMarker = Join-Path $fbTarget 'fbclient.dll'
    if (Test-Path $fbMarker) {
        Write-Host "Firebird already present: $fbTarget"
    } else {
        $local = Join-Path $DownloadDir $FB_NAME
        Get-RemoteFile -Url $FB_URL -File $local | Out-Null
        Write-Host "Extracting Firebird into $fbTarget"
        $tmp = Join-Path $DownloadDir 'fb-unpack'
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        & $7z x "-o$tmp" $local -y | Out-Null
        if ($LASTEXITCODE -ne 0) { throw '7z failed on the Firebird zip kit' }
        # the zip may wrap everything in one root folder
        $items = Get-ChildItem $tmp
        $src = if ($items.Count -eq 1 -and $items[0].PSIsContainer) { $items[0].FullName } else { $tmp }
        New-Item -ItemType Directory -Force -Path $fbTarget | Out-Null
        Copy-Item (Join-Path $src '*') $fbTarget -Force -Recurse
        Remove-Item $tmp -Recurse -Force
        if (-not (Test-Path $fbMarker)) { throw "Firebird extraction did not produce fbclient.dll under $fbTarget" }
    }
} else { Write-Host 'Firebird: skipped (-SkipFirebird)' }

# --- TagLib (static build from source) --------------------------------------
if (-not $SkipTagLib) {
    $tlInstall = Join-Path $DepsDir 'taglib-install-x64'
    $tlMarker  = Join-Path $tlInstall 'lib\tag.lib'
    if (Test-Path $tlMarker) {
        Write-Host "TagLib already present: $tlInstall"
    } else {
        $cmake = Find-CMake
        $generator = Get-VsGenerator -CMake $cmake

        $local = Join-Path $DownloadDir $TL_NAME
        Get-RemoteFile -Url $TL_URL -File $local -Algorithm SHA256 -ExpectedHash $TL_SHA256 | Out-Null

        $tlSrc = Join-Path $DepsDir 'taglib-src'
        $srcDir = Join-Path $tlSrc "taglib-$TL_VERSION"
        if (-not (Test-Path (Join-Path $srcDir 'CMakeLists.txt'))) {
            Write-Host "Extracting TagLib into $tlSrc"
            New-Item -ItemType Directory -Force -Path $tlSrc | Out-Null
            # two-step unpack: gzip first, then tar (7z keeps the inner name,
            # e.g. taglib-2.3.1.tar)
            $tar = $local -replace '\.gz$', ''
            & $7z x "-o$DownloadDir" $local -y | Out-Null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tar)) { throw '7z failed to unpack the TagLib tarball (gzip pass)' }
            & $7z x "-o$tlSrc" $tar -y | Out-Null
            if ($LASTEXITCODE -ne 0) { throw '7z failed to unpack taglib.tar' }
            Remove-Item $tar -Force
            if (-not (Test-Path (Join-Path $srcDir 'CMakeLists.txt'))) { throw "TagLib source not found under $srcDir" }
        }

        $buildDir = Join-Path $DepsDir 'taglib-build-x64'
        Write-Host "Configuring TagLib ($generator)"
        & $cmake -S $srcDir -B $buildDir -G $generator -A x64 `
            -DBUILD_SHARED_LIBS=OFF "-DCMAKE_INSTALL_PREFIX=$tlInstall"
        if ($LASTEXITCODE -ne 0) { throw 'TagLib cmake configure failed' }
        Write-Host 'Building and installing TagLib'
        & $cmake --build $buildDir --config Release --target install
        if ($LASTEXITCODE -ne 0) { throw 'TagLib build failed' }
        if (-not (Test-Path $tlMarker)) { throw "TagLib install did not produce tag.lib under $tlInstall" }
    }
} else { Write-Host 'TagLib: skipped (-SkipTagLib)' }

Write-Host ''
Write-Host 'deps layout ready:'
Get-ChildItem $DepsDir -Directory | Where-Object { $_.Name -ne 'downloads' } | ForEach-Object { "  $($_.Name)" }
Write-Host 'Run build.ps1 next.'
