param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Directory
)

$ErrorActionPreference = "Stop"

# Path to the oxipng executable
$OxipngBinary = "C:\Tools\oxipng\oxipng.exe"

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "This script requires PowerShell 7+ for -Parallel support. Run it with pwsh.exe."
    exit 1
}

if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
    Write-Error "Directory does not exist: $Directory"
    exit 1
}

if (-not (Test-Path -LiteralPath $OxipngBinary -PathType Leaf)) {
    Write-Error "oxipng binary was not found: $OxipngBinary"
    exit 1
}

# ---------------------------------------------------------------------------
# Find PNG files
# ---------------------------------------------------------------------------

$files = Get-ChildItem -LiteralPath $Directory -Filter "*.png" -File -Recurse

Write-Host ""
Write-Host "Found $($files.Count) PNG file(s)." -ForegroundColor Cyan

$coreCount = [Environment]::ProcessorCount
Write-Host "Running with $coreCount parallel oxipng process(es)." -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
# Compression (parallel, 1 process per CPU core)
# ---------------------------------------------------------------------------

$results = $files | ForEach-Object -ThrottleLimit $coreCount -Parallel {
    $file         = $_
    $oxipngBinary = $using:OxipngBinary

    $before = $file.Length

    # Lossless PNG optimization
    # -o 3         = good balance between compression and speed
    # --strip safe = remove non-essential metadata where safe
    # --preserve   = preserve original file timestamp
    & $oxipngBinary -o 3 --strip safe --preserve -- "$($file.FullName)" 2>&1 | Out-Null
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        [PSCustomObject]@{
            Path    = $file.FullName
            Success = $false
            Before  = $before
            After   = $before
        }
        return
    }

    $file.Refresh()
    $after = $file.Length

    [PSCustomObject]@{
        Path    = $file.FullName
        Success = $true
        Before  = $before
        After   = $after
    }
}

# ---------------------------------------------------------------------------
# Report per-file results (after the fact, since they ran concurrently)
# ---------------------------------------------------------------------------

$totalBefore = [int64]0
$totalAfter  = [int64]0
$processed   = 0
$failed      = 0

foreach ($r in $results) {
    $totalBefore += $r.Before
    $totalAfter  += $r.After

    if (-not $r.Success) {
        Write-Warning "Failed to compress: $($r.Path)"
        $failed++
        continue
    }

    $processed++
    $saved = $r.Before - $r.After
    $percent = if ($r.Before -gt 0) { ($saved / $r.Before) * 100 } else { 0 }

    $beforeMB = $r.Before / 1MB
    $afterMB  = $r.After / 1MB
    $savedMB  = $saved / 1MB

    Write-Host "Compressed: $($r.Path)"
    Write-Host "  $("{0:N2}" -f $beforeMB) MB -> $("{0:N2}" -f $afterMB) MB | Saved $("{0:N2}" -f $savedMB) MB ($("{0:N1}" -f $percent)%)" -ForegroundColor Green
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

$totalSaved = $totalBefore - $totalAfter
$totalPercent = if ($totalBefore -gt 0) { ($totalSaved / $totalBefore) * 100 } else { 0 }

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Compression complete" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Files found:     $($files.Count)"
Write-Host "Files processed: $processed"
Write-Host "Files failed:    $failed"
Write-Host ""
Write-Host ("Before:          {0:N2} MB" -f ($totalBefore / 1MB))
Write-Host ("After:           {0:N2} MB" -f ($totalAfter / 1MB))
Write-Host ("Total saved:     {0:N2} MB ({1:N1}%)" -f ($totalSaved / 1MB), $totalPercent) -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan