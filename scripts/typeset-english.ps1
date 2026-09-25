param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Layout,
    [Parameter(Mandatory = $true)][string]$Output
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function Get-Color([string]$hex) {
    return [System.Drawing.ColorTranslator]::FromHtml($hex)
}

function Assert-Box($box, [System.Drawing.Bitmap]$bitmap) {
    foreach ($key in @('x', 'y', 'width', 'height')) {
        if ($null -eq $box.$key) { throw "Missing layout field: $key" }
    }
    if ($box.x -lt 0 -or $box.y -lt 0 -or $box.width -le 0 -or $box.height -le 0 -or
        $box.x + $box.width -gt $bitmap.Width -or $box.y + $box.height -gt $bitmap.Height) {
        throw "Layout box is outside $($bitmap.Width)x$($bitmap.Height): $($box | ConvertTo-Json -Compress)"
    }
}

$sourceBitmap = $null
$resultBitmap = $null
$graphics = $null
try {
    $sourceBitmap = [System.Drawing.Bitmap]::new((Resolve-Path -LiteralPath $Source).Path)
    $resultBitmap = [System.Drawing.Bitmap]::new($sourceBitmap.Width, $sourceBitmap.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($resultBitmap)
    $graphics.DrawImageUnscaled($sourceBitmap, 0, 0)
    $graphics.Dispose()
    $graphics = $null

    $spec = Get-Content -LiteralPath $Layout -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($box in @($spec.erase)) {
        Assert-Box $box $sourceBitmap
        if ($box.mode -eq 'pill') {
            $radius = [Math]::Min([int]$box.radius, [int]([Math]::Min($box.width, $box.height) / 2))
            if ($radius -le 0) { throw 'Pill radius must be positive.' }
            $g = [System.Drawing.Graphics]::FromImage($resultBitmap)
            $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
            $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
                [System.Drawing.Point]::new($box.x, $box.y),
                [System.Drawing.Point]::new($box.x + $box.width, $box.y),
                (Get-Color $box.colorLeft), (Get-Color $box.colorRight))
            try {
                $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $d = 2 * $radius
                $path.AddArc($box.x, $box.y, $d, $d, 180, 90)
                $path.AddArc($box.x + $box.width - $d, $box.y, $d, $d, 270, 90)
                $path.AddArc($box.x + $box.width - $d, $box.y + $box.height - $d, $d, $d, 0, 90)
                $path.AddArc($box.x, $box.y + $box.height - $d, $d, $d, 90, 90)
                $path.CloseFigure()
                $g.FillPath($brush, $path)
            } finally {
                $brush.Dispose(); $path.Dispose(); $g.Dispose()
            }
            continue
        }
        if ($box.mode -eq 'interpolate-four-sides') {
            if ($box.x -eq 0 -or $box.y -eq 0 -or
                $box.x + $box.width -ge $sourceBitmap.Width -or
                $box.y + $box.height -ge $sourceBitmap.Height) {
                throw 'Four-side interpolation needs clean source pixels around all four edges.'
            }
            $tl = $sourceBitmap.GetPixel($box.x - 1, $box.y - 1)
            $tr = $sourceBitmap.GetPixel($box.x + $box.width, $box.y - 1)
            $bl = $sourceBitmap.GetPixel($box.x - 1, $box.y + $box.height)
            $br = $sourceBitmap.GetPixel($box.x + $box.width, $box.y + $box.height)
            foreach ($y in $box.y..($box.y + $box.height - 1)) {
                $v = ($y - $box.y + 1.0) / ($box.height + 1.0)
                $left = $sourceBitmap.GetPixel($box.x - 1, $y)
                $right = $sourceBitmap.GetPixel($box.x + $box.width, $y)
                foreach ($x in $box.x..($box.x + $box.width - 1)) {
                    $u = ($x - $box.x + 1.0) / ($box.width + 1.0)
                    $top = $sourceBitmap.GetPixel($x, $box.y - 1)
                    $bottom = $sourceBitmap.GetPixel($x, $box.y + $box.height)
                    $rgb = @()
                    foreach ($channel in @('R', 'G', 'B')) {
                        $edgeBlend = (1 - $u) * $left.$channel + $u * $right.$channel +
                            (1 - $v) * $top.$channel + $v * $bottom.$channel
                        $cornerBlend = (1 - $u) * (1 - $v) * $tl.$channel +
                            $u * (1 - $v) * $tr.$channel +
                            (1 - $u) * $v * $bl.$channel + $u * $v * $br.$channel
                        $rgb += [int][Math]::Max(0, [Math]::Min(255, [Math]::Round($edgeBlend - $cornerBlend)))
                    }
                    $resultBitmap.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($rgb[0], $rgb[1], $rgb[2]))
                }
            }
            continue
        }
        if ($box.mode -ne 'interpolate-horizontal') { throw "Unsupported erase mode: $($box.mode)" }
        if ($box.x -eq 0 -or $box.x + $box.width -ge $sourceBitmap.Width) {
            throw 'Horizontal interpolation needs a clean pixel at each side of the erase box.'
        }
        for ($y = $box.y; $y -lt $box.y + $box.height; $y++) {
            $left = $sourceBitmap.GetPixel($box.x - 1, $y)
            $right = $sourceBitmap.GetPixel($box.x + $box.width, $y)
            for ($x = $box.x; $x -lt $box.x + $box.width; $x++) {
                $t = ($x - $box.x + 1.0) / ($box.width + 1.0)
                $r = [int][Math]::Round($left.R * (1 - $t) + $right.R * $t)
                $g = [int][Math]::Round($left.G * (1 - $t) + $right.G * $t)
                $b = [int][Math]::Round($left.B * (1 - $t) + $right.B * $t)
                $resultBitmap.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($r, $g, $b))
            }
        }
    }

    $graphics = [System.Drawing.Graphics]::FromImage($resultBitmap)
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    foreach ($item in @($spec.text)) {
        Assert-Box $item $sourceBitmap
        if ([string]::IsNullOrWhiteSpace($item.value)) { throw 'Text value is empty.' }
        if ($item.size -le 0) { throw 'Font size must be positive.' }
        $style = [System.Drawing.FontStyle]::Regular
        if ($item.bold) { $style = [System.Drawing.FontStyle]::Bold }
        $family = [System.Drawing.FontFamily]::new([string]$item.font)
        $font = [System.Drawing.Font]::new($family, [single]$item.size, $style, [System.Drawing.GraphicsUnit]::Pixel)
        $brush = [System.Drawing.SolidBrush]::new((Get-Color $item.color))
        $format = [System.Drawing.StringFormat]::new([System.Drawing.StringFormat]::GenericTypographic)
        $format.FormatFlags = $format.FormatFlags -bor [System.Drawing.StringFormatFlags]::NoWrap
        $format.Alignment = if ($item.align -eq 'left') { [System.Drawing.StringAlignment]::Near } elseif ($item.align -eq 'right') { [System.Drawing.StringAlignment]::Far } else { [System.Drawing.StringAlignment]::Center }
        $format.LineAlignment = [System.Drawing.StringAlignment]::Center
        try {
            $measured = $graphics.MeasureString([string]$item.value, $font, [int]::MaxValue, $format)
            if ($measured.Width -gt $item.width -or $measured.Height -gt $item.height) {
                throw "Text exceeds its box ($([Math]::Round($measured.Width,1))x$([Math]::Round($measured.Height,1)) > $($item.width)x$($item.height)): $($item.value)"
            }
            $rect = [System.Drawing.RectangleF]::new([single]$item.x, [single]$item.y, [single]$item.width, [single]$item.height)
            $graphics.DrawString([string]$item.value, $font, $brush, $rect, $format)
        } finally {
            $format.Dispose(); $brush.Dispose(); $font.Dispose(); $family.Dispose()
        }
    }

    $outputPath = [System.IO.Path]::GetFullPath($Output)
    $directory = [System.IO.Path]::GetDirectoryName($outputPath)
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    $resultBitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output "$outputPath | $($resultBitmap.Width)x$($resultBitmap.Height)"
} finally {
    if ($graphics) { $graphics.Dispose() }
    if ($resultBitmap) { $resultBitmap.Dispose() }
    if ($sourceBitmap) { $sourceBitmap.Dispose() }
}

