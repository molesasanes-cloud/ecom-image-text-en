param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Candidate,
    [Parameter(Mandatory = $true)][string]$Regions,
    [Parameter(Mandatory = $true)][string]$Output,
    [switch]$NormalizeSameRatio,
    [ValidateRange(0, 128)][int]$FeatherPx = 12
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$sourceImage = $null
$candidateImage = $null
$result = $null
try {
    $sourceImage = [System.Drawing.Bitmap]::new((Resolve-Path -LiteralPath $Source).Path)
    $candidateImage = [System.Drawing.Bitmap]::new((Resolve-Path -LiteralPath $Candidate).Path)
    if ($sourceImage.Width -ne $candidateImage.Width -or $sourceImage.Height -ne $candidateImage.Height) {
        if (-not $NormalizeSameRatio) {
            throw "Candidate dimensions differ from source: $($candidateImage.Width)x$($candidateImage.Height) vs $($sourceImage.Width)x$($sourceImage.Height). Pass -NormalizeSameRatio only when aspect ratios match."
        }
        if ($sourceImage.Width * $candidateImage.Height -ne $sourceImage.Height * $candidateImage.Width) {
            throw 'Candidate aspect ratio differs from source; cannot normalize without cropping or distortion.'
        }
        $normalized = [System.Drawing.Bitmap]::new($sourceImage.Width, $sourceImage.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $resizeGraphics = [System.Drawing.Graphics]::FromImage($normalized)
        try {
            $resizeGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $resizeGraphics.DrawImage($candidateImage, 0, 0, $sourceImage.Width, $sourceImage.Height)
        } finally { $resizeGraphics.Dispose() }
        $candidateImage.Dispose()
        $candidateImage = $normalized
    }

    $boxes = Get-Content -LiteralPath $Regions -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($boxes -isnot [array]) { $boxes = @($boxes) }
    if ($boxes.Count -eq 0) { throw 'No approved text regions were supplied.' }

    foreach ($box in $boxes) {
        $x = [int]$box.x; $y = [int]$box.y; $w = [int]$box.width; $h = [int]$box.height
        if ($x -lt 0 -or $y -lt 0 -or $w -le 0 -or $h -le 0 -or $x + $w -gt $sourceImage.Width -or $y + $h -gt $sourceImage.Height) {
            throw "Invalid region: x=$x y=$y width=$w height=$h."
        }
        if ($FeatherPx -gt 0 -and ($w -le 2 * $FeatherPx -or $h -le 2 * $FeatherPx)) {
            throw "Region x=$x y=$y is too small for FeatherPx=$FeatherPx. Use a larger text-safe box or a smaller feather."
        }
    }

    $result = [System.Drawing.Bitmap]::new($sourceImage.Width, $sourceImage.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($result)
    try {
        $graphics.DrawImageUnscaled($sourceImage, 0, 0)
    } finally { $graphics.Dispose() }

    foreach ($box in $boxes) {
        $x0 = [int]$box.x; $y0 = [int]$box.y
        $w = [int]$box.width; $h = [int]$box.height
        if ($FeatherPx -eq 0) {
            $g = [System.Drawing.Graphics]::FromImage($result)
            try {
                $rect = [System.Drawing.Rectangle]::new($x0, $y0, $w, $h)
                $g.DrawImage($candidateImage, $rect, $rect, [System.Drawing.GraphicsUnit]::Pixel)
            } finally { $g.Dispose() }
            continue
        }
        for ($y = $y0; $y -lt $y0 + $h; $y++) {
            for ($x = $x0; $x -lt $x0 + $w; $x++) {
                $distance = [Math]::Min([Math]::Min($x - $x0 + 1, $x0 + $w - $x),
                    [Math]::Min($y - $y0 + 1, $y0 + $h - $y))
                $t = [Math]::Min(1.0, $distance / ($FeatherPx + 1.0))
                $alpha = $t * $t * (3.0 - 2.0 * $t)
                $base = $result.GetPixel($x, $y)
                $edit = $candidateImage.GetPixel($x, $y)
                $r = [int][Math]::Round($base.R * (1 - $alpha) + $edit.R * $alpha)
                $g = [int][Math]::Round($base.G * (1 - $alpha) + $edit.G * $alpha)
                $b = [int][Math]::Round($base.B * (1 - $alpha) + $edit.B * $alpha)
                $result.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($r, $g, $b))
            }
        }
    }

    $outputPath = [System.IO.Path]::GetFullPath($Output)
    if ([System.IO.Path]::GetExtension($outputPath).ToLowerInvariant() -ne '.png') { throw 'Output must be PNG to avoid JPEG re-encoding changes.' }
    $outputDir = [System.IO.Path]::GetDirectoryName($outputPath)
    if (-not [System.IO.Directory]::Exists($outputDir)) { [System.IO.Directory]::CreateDirectory($outputDir) | Out-Null }
    $result.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output "Saved $outputPath ($($result.Width)x$($result.Height)); pixels outside approved rectangles come from source; feather=$FeatherPx px."
} finally {
    if ($result) { $result.Dispose() }
    if ($candidateImage) { $candidateImage.Dispose() }
    if ($sourceImage) { $sourceImage.Dispose() }
}

