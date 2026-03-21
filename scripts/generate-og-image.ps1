Param(
  [string]$OutputPath = (Join-Path $PSScriptRoot '..\web\og-image.png')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

function New-RoundedRectanglePath {
  param(
    [double]$X,
    [double]$Y,
    [double]$Width,
    [double]$Height,
    [double]$Radius
  )

  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $diameter = $Radius * 2

  $path.AddArc($X, $Y, $diameter, $diameter, 180, 90)
  $path.AddArc($X + $Width - $diameter, $Y, $diameter, $diameter, 270, 90)
  $path.AddArc($X + $Width - $diameter, $Y + $Height - $diameter, $diameter, $diameter, 0, 90)
  $path.AddArc($X, $Y + $Height - $diameter, $diameter, $diameter, 90, 90)
  $path.CloseFigure()

  return $path
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$iconPath = Join-Path $repoRoot 'web\icons\Icon-512.png'

if (-not (Test-Path $iconPath)) {
  throw "Could not find icon source at $iconPath"
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path $outputDirectory)) {
  New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$canvasWidth = 1200
$canvasHeight = 630

$colors = @{
  Canvas = [System.Drawing.Color]::FromArgb(244, 238, 228)
  Surface = [System.Drawing.Color]::FromArgb(251, 248, 242)
  Primary = [System.Drawing.Color]::FromArgb(15, 118, 110)
  Secondary = [System.Drawing.Color]::FromArgb(180, 83, 9)
  Tertiary = [System.Drawing.Color]::FromArgb(15, 76, 129)
  Ink = [System.Drawing.Color]::FromArgb(21, 32, 51)
  Outline = [System.Drawing.Color]::FromArgb(211, 195, 178)
  MutedInk = [System.Drawing.Color]::FromArgb(96, 109, 132)
  Glow = [System.Drawing.Color]::FromArgb(46, 15, 118, 110)
  AccentGlow = [System.Drawing.Color]::FromArgb(34, 15, 76, 129)
}

$bitmap = New-Object System.Drawing.Bitmap $canvasWidth, $canvasHeight
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

$graphics.Clear($colors.Canvas)

$primaryWash = New-Object System.Drawing.SolidBrush $colors.Glow
$tertiaryWash = New-Object System.Drawing.SolidBrush $colors.AccentGlow
$graphics.FillEllipse($primaryWash, -120, -60, 420, 420)
$graphics.FillEllipse($tertiaryWash, 890, -120, 360, 360)

$cardPath = New-RoundedRectanglePath -X 56 -Y 56 -Width 1088 -Height 518 -Radius 42
$cardFill = New-Object System.Drawing.SolidBrush $colors.Surface
$cardOutline = New-Object System.Drawing.Pen $colors.Outline, 2
$graphics.FillPath($cardFill, $cardPath)
$graphics.DrawPath($cardOutline, $cardPath)

$eyebrowPath = New-RoundedRectanglePath -X 412 -Y 124 -Width 236 -Height 42 -Radius 21
$eyebrowBrush = New-Object System.Drawing.SolidBrush $colors.Primary
$graphics.FillPath($eyebrowBrush, $eyebrowPath)

$iconShadowBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(20, 21, 32, 51))
$graphics.FillEllipse($iconShadowBrush, 124, 360, 250, 42)

$iconImage = [System.Drawing.Image]::FromFile($iconPath)
$graphics.DrawImage($iconImage, 104, 158, 272, 272)

$eyebrowFont = New-Object System.Drawing.Font('Segoe UI Semibold', 20, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$titleFont = New-Object System.Drawing.Font('Segoe UI Semibold', 56, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$bodyFont = New-Object System.Drawing.Font('Segoe UI', 24, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$footerFont = New-Object System.Drawing.Font('Segoe UI Semibold', 18, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)

$whiteBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
$inkBrush = New-Object System.Drawing.SolidBrush $colors.Ink
$mutedBrush = New-Object System.Drawing.SolidBrush $colors.MutedInk
$secondaryBrush = New-Object System.Drawing.SolidBrush $colors.Secondary

$centerFormat = New-Object System.Drawing.StringFormat
$centerFormat.Alignment = [System.Drawing.StringAlignment]::Center
$centerFormat.LineAlignment = [System.Drawing.StringAlignment]::Center

$leftFormat = New-Object System.Drawing.StringFormat
$leftFormat.Alignment = [System.Drawing.StringAlignment]::Near
$leftFormat.LineAlignment = [System.Drawing.StringAlignment]::Near

$graphics.DrawString(
  'WEB-FIRST LAB',
  $eyebrowFont,
  $whiteBrush,
  (New-Object System.Drawing.RectangleF(412, 124, 236, 42)),
  $centerFormat
)

$graphics.DrawString(
  'SaaS Reliability Lab',
  $titleFont,
  $inkBrush,
  (New-Object System.Drawing.RectangleF(412, 188, 640, 78)),
  $leftFormat
)

$graphics.DrawString(
  'Inspect sync, auth, push, and offline recovery',
  $bodyFont,
  $mutedBrush,
  (New-Object System.Drawing.RectangleF(416, 312, 640, 34)),
  $leftFormat
)

$graphics.DrawString(
  'from one web-first workspace.',
  $bodyFont,
  $mutedBrush,
  (New-Object System.Drawing.RectangleF(416, 346, 640, 34)),
  $leftFormat
)

$graphics.FillRectangle($secondaryBrush, 416, 462, 180, 8)

$graphics.DrawString(
  'Flutter Web PWA | Supabase Auth',
  $footerFont,
  $inkBrush,
  (New-Object System.Drawing.RectangleF(416, 482, 640, 28)),
  $leftFormat
)

$graphics.DrawString(
  'Web Push | Runtime Diagnostics',
  $footerFont,
  $inkBrush,
  (New-Object System.Drawing.RectangleF(416, 512, 640, 28)),
  $leftFormat
)


$bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)

$iconImage.Dispose()
$centerFormat.Dispose()
$leftFormat.Dispose()
$eyebrowFont.Dispose()
$titleFont.Dispose()
$bodyFont.Dispose()
$footerFont.Dispose()
$whiteBrush.Dispose()
$inkBrush.Dispose()
$mutedBrush.Dispose()
$secondaryBrush.Dispose()
$eyebrowBrush.Dispose()
$iconShadowBrush.Dispose()
$primaryWash.Dispose()
$tertiaryWash.Dispose()
$cardOutline.Dispose()
$cardFill.Dispose()
$eyebrowPath.Dispose()
$cardPath.Dispose()
$graphics.Dispose()
$bitmap.Dispose()

Write-Host "Generated OG image at $OutputPath"