# Regenerate the original, code-drawn Ekko mark (Windows PowerShell / pwsh).
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
function Write-Icon([string]$Path, [int]$Size) {
    $bitmap = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $rect = [System.Drawing.Rectangle]::new(0, 0, $Size, $Size)
    $gradient = [System.Drawing.Drawing2D.LinearGradientBrush]::new($rect, [System.Drawing.ColorTranslator]::FromHtml('#159C90'), [System.Drawing.ColorTranslator]::FromHtml('#125D70'), [single]45)
    $g.FillRectangle($gradient, $rect)
    $g.TranslateTransform(($Size * 0.5), ($Size * 0.5))
    $g.ScaleTransform($Size, $Size)
    $geometry = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $geometry.AddLine([single]0, [single](-.19), [single]0, [single](-.31))
    $geometry.AddBezier([single]0, [single](-.31), [single]0, [single](-.40), [single]0.14, [single](-.41), [single]0.20, [single](-.31))
    $geometry.AddLine([single]0.20, [single](-.31), [single]0.30, [single](-.14))
    $geometry.AddBezier([single]0.30, [single](-.14), [single]0.35, [single](-.05), [single]0.29, [single]0.025, [single]0.21, [single]0.025)
    $geometry.AddLine([single]0.21, [single]0.025, [single]0.125, [single]0.025)
    $pen = [System.Drawing.Pen]::new([System.Drawing.ColorTranslator]::FromHtml('#F5FFF9'), [single]0.038)
    $under = [System.Drawing.Pen]::new([System.Drawing.ColorTranslator]::FromHtml('#127C78'), [single]0.075)
    foreach ($p in @($pen, $under)) {
        $p.StartCap = $p.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $p.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    }
    for ($i = 0; $i -lt 6; $i++) {
        $g.DrawPath($under, $geometry)
        $g.DrawPath($pen, $geometry)
        $g.RotateTransform(60)
    }
    $geometry.Dispose(); $under.Dispose(); $gradient.Dispose()
    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $pen.Dispose(); $g.Dispose(); $bitmap.Dispose()
}
@{mdpi=48;hdpi=72;xhdpi=96;xxhdpi=144;xxxhdpi=192}.GetEnumerator() | ForEach-Object {
    Write-Icon (Join-Path $root "android/app/src/main/res/mipmap-$($_.Key)/ic_launcher.png") $_.Value
}
$ios = Join-Path $root 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
$content = Get-Content (Join-Path $ios 'Contents.json') -Raw | ConvertFrom-Json
foreach ($image in $content.images) {
    $size = [int]([double]($image.size.Split('x')[0]) * [int]($image.scale.TrimEnd('x')))
    Write-Icon (Join-Path $ios $image.filename) $size
}
Write-Icon (Join-Path $root 'docs/app-icon.png') 512
