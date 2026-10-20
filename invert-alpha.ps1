<#
.SYNOPSIS
    Creates "-inv" copies of images that have an alpha channel, with the alpha inverted.

.DESCRIPTION
    Scans a folder for images, checks each one for an alpha channel using ImageMagick,
    and writes <name>-inv.<ext> next to the original with the alpha channel inverted.
    Existing "-inv" files are never overwritten, and "-inv" files are never used as input.
    Requires PowerShell 7+ (ForEach-Object -Parallel) and ImageMagick 7 ("magick" on PATH).

.EXAMPLE
    .\invert-alpha.ps1 -Path C:\textures -ThrottleLimit 8
    Recursion is on by default; add -NoRecurse to stay in the top folder.
    Each -inv file is written into the same folder as its original.
#>
[CmdletBinding()]
param(
    [string]$Path = (Get-Location).Path,
    [switch]$NoRecurse,
    [string[]]$Extensions = @('png', 'tga', 'tif', 'tiff', 'webp', 'dds', 'psd'),
    [int]$ThrottleLimit = [Environment]::ProcessorCount
)

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'This script needs PowerShell 7 or newer (for ForEach-Object -Parallel).'
}

$magick = Get-Command magick -ErrorAction SilentlyContinue
if (-not $magick) {
    throw 'ImageMagick ("magick") was not found on PATH.'
}
$magickPath = $magick.Source

$suffix = '-inv'
$exts = $Extensions | ForEach-Object { '.' + $_.TrimStart('.').ToLowerInvariant() }

$files = Get-ChildItem -LiteralPath $Path -File -Recurse:(-not $NoRecurse) |
    Where-Object {
        $exts -contains $_.Extension.ToLowerInvariant() -and
        -not ($_.BaseName -match '(?i)-inv(-\d+)?$')
    }

# Build the work list up front and skip anything whose output already exists
$jobs = foreach ($f in $files) {
    # img-2048 -> img-inv-2048 ; names without a trailing -<number> get "-inv" appended
    if ($f.BaseName -match '^(.*)-(\d+)$') {
        $newName = $Matches[1] + $suffix + '-' + $Matches[2]
    } else {
        $newName = $f.BaseName + $suffix
    }
    $out = Join-Path $f.DirectoryName ($newName + $f.Extension)
    if (Test-Path -LiteralPath $out) { continue }
    [pscustomobject]@{ In = $f.FullName; Out = $out }
}

$skippedExisting = @($files).Count - @($jobs).Count
Write-Host ("Found {0} image(s); {1} already have an output and are skipped." -f @($files).Count, $skippedExisting)

if (-not $jobs) { return }

$results = $jobs | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
    $in = $_.In
    $out = $_.Out
    $magick = $using:magickPath

    # Ask ImageMagick for both the alpha trait (%A) and the channel list (%[channels]).
    # Different IM versions report alpha differently, so accept either signal.
    $info = & $magick identify -format '%A|%[channels]' "${in}[0]" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $info) {
        return [pscustomobject]@{ File = $in; Status = 'Error'; Message = 'identify failed' }
    }
    $parts = ("$info").Trim() -split '\|', 2
    $alphaTrait = $parts[0].Trim()
    $channels = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }

    $hasAlpha = ($alphaTrait -match '^(Blend|True|Activate|On|Associate|Set|Copy|Transparent)$') -or
                ($channels -match '(?i)a$') -or
                ($channels -match '(?i)\balpha\b')

    if (-not $hasAlpha) {
        return [pscustomobject]@{ File = $in; Status = 'NoAlpha'; Message = "A='$alphaTrait' channels='$channels'" }
    }

    # Re-check right before writing in case another run created it meanwhile
    if (Test-Path -LiteralPath $out) {
        return [pscustomobject]@{ File = $in; Status = 'Exists'; Message = '' }
    }

    $err = & $magick $in -channel A -negate +channel $out 2>&1
    if ($LASTEXITCODE -ne 0) {
        return [pscustomobject]@{ File = $in; Status = 'Error'; Message = ($err | Out-String).Trim() }
    }
    [pscustomobject]@{ File = $in; Status = 'Created'; Message = $out }
}

$results | Where-Object Status -eq 'Error' | ForEach-Object {
    Write-Warning "$($_.File): $($_.Message)"
}

$results | Where-Object Status -eq 'NoAlpha' | Select-Object -First 3 | ForEach-Object {
    Write-Verbose "No alpha detected: $($_.File) ($($_.Message))"
}

$summary = $results | Group-Object Status | ForEach-Object { '{0}: {1}' -f $_.Name, $_.Count }
Write-Host ($summary -join ', ')
