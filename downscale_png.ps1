#Requires -Version 7.0
<#
.SYNOPSIS
    Recursively finds PNGs whose names contain "-<FromSize>" (e.g. texture-2048-albedo.png),
    downscales them in parallel, and writes maximally compressed copies next to them with
    "-<ToSize>" in the name instead.

.EXAMPLE
    .\downscale_png.ps1 .\textures 2048 1024
    textures\wood-2048-albedo.png -> textures\wood-1024-albedo.png (fit within 1024x1024)

.EXAMPLE
    .\downscale_png.ps1 .\textures 2048 1024 -Force -ThrottleLimit 4 -Strip
    Overwrite existing outputs, use 4 parallel jobs, and drop metadata chunks.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Directory,

    [Parameter(Mandatory, Position = 1)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$FromSize,

    [Parameter(Mandatory, Position = 2)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$ToSize,

    # Number of ImageMagick processes running at once (default: number of CPU cores)
    [ValidateRange(1, 256)]
    [int]$ThrottleLimit = [Environment]::ProcessorCount,

    # Overwrite existing output files (default: skip them)
    [switch]$Force,

    # Remove metadata (EXIF, ICC profile, text chunks) for smaller files.
    # Note: dropping an ICC profile can slightly change how colors display.
    [switch]$Strip
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
    throw "'$Directory' is not a directory"
}
if ($ToSize -ge $FromSize) {
    throw "ToSize ($ToSize) must be smaller than FromSize ($FromSize)"
}

# Only use "magick": on Windows, "convert" is a built-in disk utility, not ImageMagick.
if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
    throw "ImageMagick ('magick') not found in PATH. Install it from https://imagemagick.org or via 'winget install ImageMagick.ImageMagick'."
}

# "-<from>" followed by a non-digit (so -2048 doesn't match -20481).
# Greedy prefix means the last occurrence is the one replaced.
$pattern = "^(.*)-$($FromSize)([^0-9].*)$"

# Build the job list up front (on the main thread) so skipping is reported in order.
$jobs = [System.Collections.Generic.List[object]]::new()
$skipped = 0

Get-ChildItem -LiteralPath $Directory -Recurse -File -Filter '*.png' | ForEach-Object {
    if ($_.Name -notmatch $pattern) { return }

    $out = Join-Path $_.DirectoryName "$($Matches[1])-$($ToSize)$($Matches[2])"

    if ((Test-Path -LiteralPath $out) -and -not $Force) {
        Write-Host "Skip (exists): $out"
        $skipped++
        return
    }
    $jobs.Add([pscustomobject]@{ In = $_.FullName; Out = $out })
}

if ($jobs.Count -eq 0) {
    Write-Host "Nothing to do. ($skipped skipped)"
    return
}

Write-Host "Converting $($jobs.Count) file(s) with up to $ThrottleLimit parallel job(s)..."

$results = $jobs | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
    $job = $_
    $size = $using:ToSize

    # Max PNG compression: zlib level 9 with adaptive per-row filtering (filter type 5).
    # ">" in the geometry only shrinks, never enlarges; aspect ratio is preserved.
    $args = @(
        $job.In
        '-resize', "$($size)x$($size)>"
        '-define', 'png:compression-level=9'
        '-define', 'png:compression-filter=5'
    )
    if ($using:Strip) { $args += '-strip' }
    $args += $job.Out

    & magick @args
    $ok = ($LASTEXITCODE -eq 0)

    if ($ok) { Write-Host "$($job.In) -> $($job.Out)" }
    else     { Write-Warning "magick failed for $($job.In)" }

    [pscustomobject]@{ Ok = $ok }
}

$converted = @($results | Where-Object Ok).Count
$failed = $jobs.Count - $converted
Write-Host "Done: $converted converted, $skipped skipped, $failed failed."
if ($failed -gt 0) { exit 1 }
