[CmdletBinding()]
param(
  [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\branding')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceSvg = Join-Path $repoRoot 'assets\branding\bd-auto-brand-banner.svg'
if (-not (Test-Path -LiteralPath $sourceSvg)) {
  throw "Branding source SVG was not found: $sourceSvg"
}

$resolvedOutput = [System.IO.Path]::GetFullPath($OutputRoot)
if (-not $resolvedOutput.StartsWith([System.IO.Path]::GetFullPath($repoRoot), [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "Unsafe branding output path: $resolvedOutput"
}

New-Item -ItemType Directory -Force -Path $resolvedOutput | Out-Null

function New-Brush([string]$startHex, [string]$endHex, [int]$width, [int]$height, [int]$mode = 1) {
  $start = [System.Drawing.ColorTranslator]::FromHtml($startHex)
  $end = [System.Drawing.ColorTranslator]::FromHtml($endHex)
  return New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.Rectangle 0, 0, $width, $height),
    $start,
    $end,
    $mode
  )
}

function Draw-HudFrame($g, $pen, [int]$x, [int]$y, [int]$w, [int]$h) {
  $points = [System.Drawing.Point[]]@(
    (New-Object System.Drawing.Point ($x + 12), $y),
    (New-Object System.Drawing.Point ($x + $w - 12), $y),
    (New-Object System.Drawing.Point ($x + $w), ($y + 12)),
    (New-Object System.Drawing.Point ($x + $w), ($y + $h - 12)),
    (New-Object System.Drawing.Point ($x + $w - 12), ($y + $h)),
    (New-Object System.Drawing.Point ($x + 12), ($y + $h)),
    (New-Object System.Drawing.Point $x, ($y + $h - 12)),
    (New-Object System.Drawing.Point $x, ($y + 12))
  )
  $g.DrawPolygon($pen, $points)
}

function Draw-Title([System.Drawing.Graphics]$g, [string]$text, [System.Drawing.Font]$font, [System.Drawing.Brush]$brush, [float]$x, [float]$y) {
  $sf = New-Object System.Drawing.StringFormat
  $sf.Alignment = [System.Drawing.StringAlignment]::Center
  $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
  $g.DrawString($text, $font, $brush, $x, $y, $sf)
  $sf.Dispose()
}

function Save-Bitmap([System.Drawing.Bitmap]$bitmap, [string]$path) {
  $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Bmp)
}

function Draw-LargeWizard([string]$path) {
  $w = 202
  $h = 386
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  try {
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.ColorTranslator]::FromHtml('#0b0d12'))
    $bg = New-Brush '#0b0d12' '#171922' $w $h 2
    $g.FillRectangle($bg, 0, 0, $w, $h)
    $bg.Dispose()

    $gridPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(24, 86, 104, 139)), 1
    for ($i = 0; $i -lt 10; $i++) {
      $g.DrawLine($gridPen, 0, (22 * $i), $w, (22 * $i))
    }
    for ($i = 0; $i -lt 6; $i++) {
      $g.DrawLine($gridPen, (33 * $i), 0, (33 * $i), $h)
    }

    $ringPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(58, 106, 128, 165)), 2
    $g.DrawEllipse($ringPen, 38, 34, 126, 126)
    $g.DrawEllipse($ringPen, 20, 16, 162, 162)

    $steelPen = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml('#dde5f6'), 10)
    $steelPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $glowPen = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml('#6c7fff'), 6)
    $glowPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $centerPen = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml('#89b9ff'), 4)

    $outer = [System.Drawing.Point[]]@(
      [System.Drawing.Point]::new(101, 40),
      [System.Drawing.Point]::new(145, 66),
      [System.Drawing.Point]::new(145, 118),
      [System.Drawing.Point]::new(101, 144),
      [System.Drawing.Point]::new(57, 118),
      [System.Drawing.Point]::new(57, 66)
    )
    $inner = [System.Drawing.Point[]]@(
      [System.Drawing.Point]::new(101, 70),
      [System.Drawing.Point]::new(122, 82),
      [System.Drawing.Point]::new(122, 106),
      [System.Drawing.Point]::new(101, 118),
      [System.Drawing.Point]::new(80, 106),
      [System.Drawing.Point]::new(80, 82)
    )
    $g.DrawPolygon($steelPen, $outer)
    $g.DrawPolygon($glowPen, $inner)
    $g.DrawEllipse($centerPen, 92, 89, 18, 18)
    $g.DrawLine($centerPen, 101, 24, 101, 54)
    $g.DrawLine($centerPen, 101, 144, 101, 178)

    $fontBig = New-Object System.Drawing.Font 'Segoe UI', 26, ([System.Drawing.FontStyle]::Bold)
    $fontMid = New-Object System.Drawing.Font 'Segoe UI', 8.1, ([System.Drawing.FontStyle]::Regular)
    $fontSmall = New-Object System.Drawing.Font 'Segoe UI', 7.0, ([System.Drawing.FontStyle]::Regular)
    $whiteBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#eff3fb'))
    $blueBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#93b7ff'))
    $mutedBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#99a7be'))

    Draw-Title $g 'BD-AUTO' $fontBig $whiteBrush 101 218
    Draw-Title $g 'SMART REPAIR UTILITY' $fontMid $mutedBrush 101 243
    Draw-Title $g 'REPAIR. VERIFY. RELAUNCH.' $fontMid $blueBrush 101 266

    $framePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(116, 58, 74, 96)), 1
    Draw-HudFrame $g $framePen 14 286 174 86
    $g.DrawString('BD PATCH STATUS', $fontSmall, $whiteBrush, 26, 300)
    $g.DrawString('bdcli-first verified', $fontSmall, $mutedBrush, 26, 316)
    $g.DrawString('ADDON SYNC', $fontSmall, $whiteBrush, 26, 334)
    $g.DrawString('source-aware restore', $fontSmall, $mutedBrush, 26, 350)

    Save-Bitmap $bmp $path

    $framePen.Dispose()
    $fontBig.Dispose(); $fontMid.Dispose(); $fontSmall.Dispose()
    $whiteBrush.Dispose(); $blueBrush.Dispose(); $mutedBrush.Dispose()
    $steelPen.Dispose(); $glowPen.Dispose(); $centerPen.Dispose()
    $ringPen.Dispose(); $gridPen.Dispose()
  } finally {
    $g.Dispose()
    $bmp.Dispose()
  }
}

function Draw-SmallWizard([string]$path) {
  $w = 147
  $h = 147
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  try {
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $bg = New-Brush '#0d1118' '#1a1e28' $w $h 2
    $g.FillRectangle($bg, 0, 0, $w, $h)
    $bg.Dispose()

    $ringPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(52, 93, 109, 144)), 2
    $g.DrawEllipse($ringPen, 20, 16, 106, 106)
    $g.DrawEllipse($ringPen, 8, 4, 130, 130)

    $steelPen = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml('#dce4f7'), 8)
    $steelPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $glowPen = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml('#7284ff'), 5)
    $glowPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $centerBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#90bcff'))
    $titleBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#eef2fa'))

    $outer = [System.Drawing.Point[]]@(
      [System.Drawing.Point]::new(73, 28),
      [System.Drawing.Point]::new(106, 47),
      [System.Drawing.Point]::new(106, 88),
      [System.Drawing.Point]::new(73, 107),
      [System.Drawing.Point]::new(40, 88),
      [System.Drawing.Point]::new(40, 47)
    )
    $inner = [System.Drawing.Point[]]@(
      [System.Drawing.Point]::new(73, 51),
      [System.Drawing.Point]::new(89, 60),
      [System.Drawing.Point]::new(89, 75),
      [System.Drawing.Point]::new(73, 84),
      [System.Drawing.Point]::new(57, 75),
      [System.Drawing.Point]::new(57, 60)
    )
    $g.DrawPolygon($steelPen, $outer)
    $g.DrawPolygon($glowPen, $inner)
    $g.FillEllipse($centerBrush, 68, 64, 10, 10)

    $font = New-Object System.Drawing.Font 'Segoe UI', 12, ([System.Drawing.FontStyle]::Bold)
    Draw-Title $g 'BD-AUTO' $font $titleBrush 73 126

    Save-Bitmap $bmp $path

    $font.Dispose()
    $titleBrush.Dispose()
    $centerBrush.Dispose()
    $glowPen.Dispose()
    $steelPen.Dispose()
    $ringPen.Dispose()
  } finally {
    $g.Dispose()
    $bmp.Dispose()
  }
}

function Draw-Icon([string]$path) {
  $w = 256
  $h = 256
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  try {
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $bg = New-Brush '#0c0f15' '#1b1f29' $w $h 2
    $g.FillRectangle($bg, 0, 0, $w, $h)
    $bg.Dispose()

    $ringPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(58, 104, 120, 160)), 3
    $g.DrawEllipse($ringPen, 28, 28, 200, 200)
    $g.DrawEllipse($ringPen, 12, 12, 232, 232)

    $steelPen = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml('#e1e7f6'), 16)
    $steelPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $glowPen = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml('#7185ff'), 10)
    $glowPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $coreBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#8dbbff'))

    $outer = [System.Drawing.Point[]]@(
      [System.Drawing.Point]::new(128, 42),
      [System.Drawing.Point]::new(183, 74),
      [System.Drawing.Point]::new(183, 141),
      [System.Drawing.Point]::new(128, 174),
      [System.Drawing.Point]::new(73, 141),
      [System.Drawing.Point]::new(73, 74)
    )
    $inner = [System.Drawing.Point[]]@(
      [System.Drawing.Point]::new(128, 86),
      [System.Drawing.Point]::new(155, 101),
      [System.Drawing.Point]::new(155, 115),
      [System.Drawing.Point]::new(128, 130),
      [System.Drawing.Point]::new(101, 115),
      [System.Drawing.Point]::new(101, 101)
    )
    $g.DrawPolygon($steelPen, $outer)
    $g.DrawPolygon($glowPen, $inner)
    $g.FillEllipse($coreBrush, 120, 103, 16, 16)
    $g.DrawLine($glowPen, 128, 16, 128, 55)
    $g.DrawLine($glowPen, 128, 174, 128, 236)

    $font = New-Object System.Drawing.Font 'Segoe UI', 24, ([System.Drawing.FontStyle]::Bold)
    $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#eef2fa'))
    Draw-Title $g 'BD' $font $brush 128 214

    $hIcon = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($hIcon)
    $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Create)
    try {
      $icon.Save($fs)
    } finally {
      $fs.Dispose()
      $icon.Dispose()
    }

    $font.Dispose()
    $brush.Dispose()
    $coreBrush.Dispose()
    $glowPen.Dispose()
    $steelPen.Dispose()
    $ringPen.Dispose()
  } finally {
    $g.Dispose()
    $bmp.Dispose()
  }
}

$large = Join-Path $resolvedOutput 'wizard-sidebar.bmp'
$small = Join-Path $resolvedOutput 'wizard-header.bmp'
$icon = Join-Path $resolvedOutput 'bd-auto-setup.ico'

Draw-LargeWizard -path $large
Draw-SmallWizard -path $small
Draw-Icon -path $icon

[pscustomobject]@{
  SourceSvg = $sourceSvg
  WizardSidebar = $large
  WizardHeader = $small
  SetupIcon = $icon
} | ConvertTo-Json
