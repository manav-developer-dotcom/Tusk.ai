# Generates Android mipmap launcher icons from a source JPG/PNG
# Uses System.Drawing (built-in .NET) — no extra tools needed

param(
    [string]$SourceImage = "C:\Users\Test\.gemini\antigravity-ide\brain\99119877-a780-45ad-b114-34018e24f438\tusk_icon_clean_1792178078190.jpg",
    [string]$ResDir     = "C:\Users\Test\Desktop\Husk.ai\app\android\app\src\main\res"
)

Add-Type -AssemblyName System.Drawing

# Android mipmap density → launcher icon pixel size
$densities = @{
    "mipmap-mdpi"    = 48
    "mipmap-hdpi"    = 72
    "mipmap-xhdpi"   = 96
    "mipmap-xxhdpi"  = 144
    "mipmap-xxxhdpi" = 192
}

function Resize-Image {
    param(
        [System.Drawing.Image]$src,
        [int]$size,
        [string]$destPath
    )
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($src, 0, 0, $size, $size)
    $g.Dispose()
    $bmp.Save($destPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

$src = [System.Drawing.Image]::FromFile($SourceImage)

foreach ($density in $densities.GetEnumerator()) {
    $folder = Join-Path $ResDir $density.Key
    if (-not (Test-Path $folder)) { New-Item -ItemType Directory -Path $folder | Out-Null }

    $size = $density.Value

    # ic_launcher (rounded by OS)
    Resize-Image -src $src -size $size -destPath (Join-Path $folder "ic_launcher.png")

    # ic_launcher_background (solid black background layer)
    $bgBmp = New-Object System.Drawing.Bitmap($size, $size)
    $gBg   = [System.Drawing.Graphics]::FromImage($bgBmp)
    $gBg.Clear([System.Drawing.Color]::Black)
    $gBg.Dispose()
    $bgBmp.Save((Join-Path $folder "ic_launcher_background.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $bgBmp.Dispose()

    # ic_launcher_foreground (same as ic_launcher for simplicity — white text on black)
    Resize-Image -src $src -size $size -destPath (Join-Path $folder "ic_launcher_foreground.png")

    Write-Host "[$($density.Key)] Generated $size x $size icons"
}

$src.Dispose()

# Also generate the launch_background foreground bitmap at 192px for use in splash
$splash = [System.Drawing.Image]::FromFile($SourceImage)
$splashOut = Join-Path $ResDir "mipmap-xxxhdpi\ic_launcher_foreground.png"
# already done above

$splash.Dispose()

Write-Host ""
Write-Host "All launcher icons generated successfully."
