# Regenerate the original, code-drawn Ekko mark (Windows PowerShell / pwsh).
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
function Write-Icon([string]$Path, [int]$Size) {
    $bitmap = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.ColorTranslator]::FromHtml('#245B46'))
    $pen = [System.Drawing.Pen]::new([System.Drawing.ColorTranslator]::FromHtml('#F7F5ED'), ($Size * 0.065))
    $pen.StartCap = $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    for ($i = 0; $i -lt 3; $i++) {
        $x = $Size * (0.27 + $i * 0.23)
        $g.DrawBezier($pen, [single]$x, [single]($Size*0.34), [single]($x-$Size*0.087), [single]($Size*0.447), [single]($x-$Size*0.087), [single]($Size*0.553), [single]$x, [single]($Size*0.66))
    }
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
