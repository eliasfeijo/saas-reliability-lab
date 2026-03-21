Param(
  [string]$WebIconsDirectory = (Join-Path $PSScriptRoot '..\web\icons'),
  [string]$FaviconPath = (Join-Path $PSScriptRoot '..\web\favicon.png'),
  [string]$WindowsIconPath = (Join-Path $PSScriptRoot '..\windows\runner\resources\app_icon.ico')
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

function New-BrandBitmap {
  param(
    [int]$Size,
    [bool]$Maskable = $false
  )

  $colors = @{
    Canvas = [System.Drawing.Color]::FromArgb(244, 238, 228)
    Surface = [System.Drawing.Color]::FromArgb(251, 248, 242)
    Primary = [System.Drawing.Color]::FromArgb(15, 118, 110)
    Secondary = [System.Drawing.Color]::FromArgb(180, 83, 9)
    Tertiary = [System.Drawing.Color]::FromArgb(15, 76, 129)
    Ink = [System.Drawing.Color]::FromArgb(21, 32, 51)
    Outline = [System.Drawing.Color]::FromArgb(211, 195, 178)
    Glow = [System.Drawing.Color]::FromArgb(36, 15, 118, 110)
  }

  $bitmap = New-Object System.Drawing.Bitmap $Size, $Size
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

  $graphics.Clear($colors.Canvas)

  $glowBrush = New-Object System.Drawing.SolidBrush $colors.Glow
  $graphics.FillEllipse($glowBrush, -($Size * 0.08), $Size * 0.05, $Size * 0.46, $Size * 0.46)

  $panelMargin = [int]([Math]::Round($Size * ($(if ($Maskable) { 0.16 } else { 0.15 }))))
  $panelSize = $Size - ($panelMargin * 2)
  $panelRadius = [int]([Math]::Round($Size * 0.17))
  $panelPath = New-RoundedRectanglePath -X $panelMargin -Y $panelMargin -Width $panelSize -Height $panelSize -Radius $panelRadius
  $panelFill = New-Object System.Drawing.SolidBrush $colors.Surface
  $panelOutline = New-Object System.Drawing.Pen $colors.Ink, ([Math]::Max(4, [int]([Math]::Round($Size * 0.035))))
  $graphics.FillPath($panelFill, $panelPath)
  $graphics.DrawPath($panelOutline, $panelPath)

  $barWidth = [int]([Math]::Round($Size * 0.094))
  $barRadius = [int]([Math]::Round($barWidth / 2))
  $barConfigs = @(
    @{ X = 0.20; Y = 0.54; Height = 0.23; Color = $colors.Primary },
    @{ X = 0.42; Y = 0.42; Height = 0.35; Color = $colors.Secondary },
    @{ X = 0.64; Y = 0.28; Height = 0.49; Color = $colors.Tertiary }
  )

  foreach ($barConfig in $barConfigs) {
    $barHeight = [int]([Math]::Round($panelSize * $barConfig.Height))
    $barX = [int]([Math]::Round($panelMargin + ($panelSize * $barConfig.X)))
    $barY = [int]([Math]::Round($panelMargin + ($panelSize * $barConfig.Y)))
    $barPath = New-RoundedRectanglePath -X $barX -Y $barY -Width $barWidth -Height $barHeight -Radius $barRadius
    $barBrush = New-Object System.Drawing.SolidBrush $barConfig.Color
    $graphics.FillPath($barBrush, $barPath)
    $barBrush.Dispose()
    $barPath.Dispose()
  }

  $tracePen = New-Object System.Drawing.Pen $colors.Ink, ([Math]::Max(4, [int]([Math]::Round($Size * 0.043))))
  $tracePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $tracePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $tracePen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round

  $points = [System.Drawing.PointF[]]@(
    (New-Object System.Drawing.PointF(($panelMargin + ($panelSize * 0.14)), ($panelMargin + ($panelSize * 0.67)))),
    (New-Object System.Drawing.PointF(($panelMargin + ($panelSize * 0.30)), ($panelMargin + ($panelSize * 0.67)))),
    (New-Object System.Drawing.PointF(($panelMargin + ($panelSize * 0.44)), ($panelMargin + ($panelSize * 0.49)))),
    (New-Object System.Drawing.PointF(($panelMargin + ($panelSize * 0.56)), ($panelMargin + ($panelSize * 0.49)))),
    (New-Object System.Drawing.PointF(($panelMargin + ($panelSize * 0.69)), ($panelMargin + ($panelSize * 0.33)))),
    (New-Object System.Drawing.PointF(($panelMargin + ($panelSize * 0.82)), ($panelMargin + ($panelSize * 0.33))))
  )
  $graphics.DrawLines($tracePen, $points)

  $nodeRadius = [int]([Math]::Round($Size * 0.034))
  $nodeBrush = New-Object System.Drawing.SolidBrush $colors.Ink
  foreach ($point in @($points[2], $points[4])) {
    $graphics.FillEllipse($nodeBrush, $point.X - $nodeRadius, $point.Y - $nodeRadius, $nodeRadius * 2, $nodeRadius * 2)
  }

  $nodeBrush.Dispose()
  $tracePen.Dispose()
  $panelOutline.Dispose()
  $panelFill.Dispose()
  $panelPath.Dispose()
  $glowBrush.Dispose()
  $graphics.Dispose()

  return $bitmap
}

function Write-PngIcon {
  param(
    [int]$Size,
    [string]$OutputPath,
    [bool]$Maskable = $false
  )

  $bitmap = New-BrandBitmap -Size $Size -Maskable:$Maskable
  $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
  $bitmap.Dispose()
}

function Write-IcoIcon {
  param(
    [string]$OutputPath
  )

  $bitmap = New-BrandBitmap -Size 256
  $icon = [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())
  $stream = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::Create)
  $icon.Save($stream)
  $stream.Dispose()
  $icon.Dispose()
  $bitmap.Dispose()
}

if (-not (Test-Path $WebIconsDirectory)) {
  New-Item -ItemType Directory -Path $WebIconsDirectory | Out-Null
}

$faviconDirectory = Split-Path -Parent $FaviconPath
if (-not (Test-Path $faviconDirectory)) {
  New-Item -ItemType Directory -Path $faviconDirectory | Out-Null
}

$windowsIconDirectory = Split-Path -Parent $WindowsIconPath
if (-not (Test-Path $windowsIconDirectory)) {
  New-Item -ItemType Directory -Path $windowsIconDirectory | Out-Null
}

Write-PngIcon -Size 192 -OutputPath (Join-Path $WebIconsDirectory 'Icon-192.png')
Write-PngIcon -Size 512 -OutputPath (Join-Path $WebIconsDirectory 'Icon-512.png')
Write-PngIcon -Size 192 -OutputPath (Join-Path $WebIconsDirectory 'Icon-maskable-192.png') -Maskable:$true
Write-PngIcon -Size 512 -OutputPath (Join-Path $WebIconsDirectory 'Icon-maskable-512.png') -Maskable:$true
Write-PngIcon -Size 64 -OutputPath $FaviconPath
Write-IcoIcon -OutputPath $WindowsIconPath

Write-Host 'Generated brand icons for web and Windows resources.'