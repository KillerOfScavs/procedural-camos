<#
.SYNOPSIS
    Recursively sets the RGB color of all PNGs that have an alpha channel to
    255,255,255 (white) while keeping the alpha channel. Replaces the originals.

.USAGE
    .\whiten-png-alpha.ps1                 # current directory
    .\whiten-png-alpha.ps1 -Path C:\Images # specific folder
    .\whiten-png-alpha.ps1 -WhatIf         # dry run, nothing is changed

    Requires ImageMagick 7 ("magick" in PATH).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Path = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
    throw "ImageMagick ('magick') was not found in PATH."
}

$files = Get-ChildItem -LiteralPath $Path -Recurse -File -Filter *.png
$processed = 0
$skipped   = 0
$failed    = 0

foreach ($file in $files) {
    try {
        # Collect several indicators, since the output of %[channels] differs between
        # ImageMagick versions (newer ones report "srgb" even when alpha is present).
        #   %A                          -> Blend/True = has alpha, Undefined/False = none
        #   %[channels]                 -> ends with "a" in some versions (srgba, graya)
        #   png:IHDR.color-type-orig    -> 4 (gray+alpha) or 6 (RGBA); 3 = palette (may have tRNS)
        $info = (& magick identify -quiet -format '%A|%[channels]|%[png:IHDR.color-type-orig]|%[png:tRNS]' "$($file.FullName)[0]" 2>$null)
        if ($LASTEXITCODE -ne 0 -or -not $info) { throw "identify failed" }

        $parts     = ($info | Select-Object -First 1) -split '\|'
        $alphaFlag = $parts[0]
        $channels  = $parts[1]
        $colorType = $parts[2]
        $trns      = $parts[3]

        $hasAlpha = ($alphaFlag -match '^(Blend|True|Activate|On|Associate|Set|Transparent)$') -or
                    ($channels -match 'a$') -or
                    ($colorType -in @('4', '6')) -or
                    ($colorType -eq '3' -and $trns)

        Write-Verbose "$($file.Name): A=$alphaFlag channels=$channels colortype=$colorType hasAlpha=$hasAlpha"

        if (-not $hasAlpha) {
            $skipped++
            continue
        }

        if ($PSCmdlet.ShouldProcess($file.FullName, 'Set color to white, keep alpha')) {
            $tmp = Join-Path $file.DirectoryName ([guid]::NewGuid().ToString() + '.png')
            try {
                # Set R,G,B to 100% (white); alpha channel is left untouched.
                & magick "$($file.FullName)" `
                    -channel RGB -evaluate set 100% +channel `
                    -define png:color-type=6 `
                    "PNG32:$tmp"
                if ($LASTEXITCODE -ne 0) { throw "magick failed" }

                Move-Item -LiteralPath $tmp -Destination $file.FullName -Force
                $processed++
                Write-Host "Processed: $($file.FullName)"
            }
            finally {
                if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
            }
        }
    }
    catch {
        $failed++
        Write-Warning "Failed: $($file.FullName) - $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "Done. Processed: $processed | Skipped (no alpha): $skipped | Failed: $failed"