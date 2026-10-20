<#
.SYNOPSIS
    Recursively finds images whose file name/path contains a given string (and none of the
    excluded strings), then builds a black & white (grayscale) contact-sheet grid PNG with
    ImageMagick using maximum PNG compression.

.EXAMPLE
    .\Make-ImageGrid.ps1 -SearchString "vacation" -Path "D:\Pictures"

.EXAMPLE
    # Exclude paths/names containing "thumb" or "backup"
    .\Make-ImageGrid.ps1 -SearchString "sunset" -ExcludeString "thumb","backup" -Columns 6 -TileSize 300 -Labels -Output sunsets.png
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$SearchString,

    [string[]]$ExcludeString = @(),   # skip any image whose full path contains one of these

    [string]$Path = '.',
    [string]$Output = 'grid.png',
    [int]$Columns = 5,
    [int]$TileSize = 256,
    [switch]$Labels            # print the file name under each tile
)

$ErrorActionPreference = 'Stop'

# --- Check ImageMagick (v7 'magick') ---
if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
    throw "ImageMagick ('magick') was not found in PATH. Install it from https://imagemagick.org and restart the shell."
}

$imageExtensions = '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.tif', '.tiff'
$root       = (Resolve-Path -LiteralPath $Path).Path
$outputFull = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Output))

# Ignore empty exclude entries (an empty string would match everything)
$excludes = @($ExcludeString | Where-Object { -not [string]::IsNullOrEmpty($_) })

$excludeInfo = if ($excludes.Count) { " (excluding: $($excludes -join ', '))" } else { '' }
Write-Host "Scanning '$root' for images matching '$SearchString'$excludeInfo ..."

$matchedFiles = [System.Collections.Generic.List[string]]::new()

Get-ChildItem -LiteralPath $root -Recurse -File |
    Where-Object { $imageExtensions -contains $_.Extension.ToLower() -and $_.FullName -ne $outputFull } |
    ForEach-Object {
        $full = $_.FullName

        if ($full.IndexOf($SearchString, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { return }

        foreach ($ex in $excludes) {
            if ($full.IndexOf($ex, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return }
        }

        $matchedFiles.Add($full)
        Write-Host "  + $full"
    }

if ($matchedFiles.Count -eq 0) {
    Write-Warning "No matching images found."
    return
}

Write-Host "`n$($matchedFiles.Count) image(s) matched."

# --- Temporary list file (avoids command-line length limits); deleted when done ---
# UTF-8 without BOM so ImageMagick reads the first line correctly.
# For multi-frame formats only the first frame is used ([0]).
$tempList = [System.IO.Path]::GetTempFileName()

try {
    $lines = $matchedFiles | ForEach-Object {
        if ($_ -match '\.(gif|webp|tif|tiff)$') { "$_[0]" } else { $_ }
    }
    [System.IO.File]::WriteAllLines($tempList, [string[]]$lines, (New-Object System.Text.UTF8Encoding($false)))

    # --- Build the grid: grayscale, PNG, maximum compression ---
    $montageArgs = @('montage')
    if ($Labels) { $montageArgs += @('-label', '%f', '-pointsize', '12', '-fill', 'white') }
    $montageArgs += "@$tempList"
    $montageArgs += @(
        '-tile', "${Columns}x",
        '-geometry', "${TileSize}x${TileSize}+6+6",
        '-background', 'transparent',
        '-colorspace', 'Gray',
        '-depth', '8',
        '-strip',
        '-define', 'png:compression-level=9',
        '-define', 'png:compression-filter=5',
        '-define', 'png:compression-strategy=1',
        "png:$outputFull"
    )

    & magick @montageArgs
    if ($LASTEXITCODE -ne 0) {
        throw "ImageMagick montage failed (exit code $LASTEXITCODE)."
    }

    Write-Host "Grid created: $outputFull"
}
finally {
    Remove-Item -LiteralPath $tempList -Force -ErrorAction SilentlyContinue
}
