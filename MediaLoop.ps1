Add-Type -AssemblyName PresentationFramework, WindowsBase

# --- CONTROL VARIABLES ---
# Default Sequence: List of objects with [Path] and [Duration]
$DefaultSequence = @(
    @{ Path = "C:\Users\paulc\Desktop\AIFairPresentation\AIFairFlyer.png"; Duration = 3 },
    @{ Path = "C:\Users\paulc\Desktop\AIFairPresentation\AIFairSchedule.png";    Duration = 5 }
    # Add more lines here as needed: @{ Path = "C:\Path\To\File.png"; Duration = 10 }
)

# Random Media Settings
$RandomFolder       = "C:\Users\paulc\Desktop\AIFairPresentation\RandomMedia"
$Time_Graphic       = 5    # Duration for static random images
$Time_Video         = 8    # Duration for random videos
$MaxRandomPerLoop   = 5    # Absolute maximum randoms before returning to defaults
$RandomTargetValue  = 0.6  # Probability (0.0 to 1.0) to play another random media

# Visual Settings
$AlwaysOnTop = $true
# --------------------------

# Initialize background UI thread
$syncHash = [hashtable]::Synchronized(@{})
$newRunspace = [runspacefactory]::CreateRunspace()
$newRunspace.ApartmentState = "STA"
$newRunspace.Open()

$code = {
    $window = New-Object Windows.Window
    $window.WindowStyle, $window.WindowState, $window.Background = "None", "Maximized", "Black"
    $window.Topmost = $args[1]
    $media = New-Object Windows.Controls.MediaElement
    $media.Stretch, $media.LoadedBehavior = "Uniform", "Manual"
    $window.Content = $media
    $window.Show()
    ($args[0]).Media, ($args[0]).Window = $media, $window
    [System.Windows.Threading.Dispatcher]::Run()
}

$powershell = [powershell]::Create().AddScript($code).AddArgument($syncHash).AddArgument($AlwaysOnTop)
$powershell.Runspace = $newRunspace
$powershell.BeginInvoke()

$PlayedFiles = @()
Start-Sleep -Seconds 2

try {
    while ($true) {
        # 1. PLAY DEFAULTS
        foreach ($Item in $DefaultSequence) {
            if (Test-Path $Item.Path) {
                Write-Host "Default: $($Item.Path) ($($Item.Duration)s)"
                $syncHash.CurrentPath = $Item.Path
                $syncHash.Media.Dispatcher.Invoke([Action]{
                    $syncHash.Media.Source = [System.Uri]$syncHash.CurrentPath
                    $syncHash.Media.Play()
                })
                Start-Sleep -Seconds $Item.Duration
            }
        }

        # 2. PLAY RANDOM MEDIA (PROBABILISTIC)
        $LoopRandomCount = 0
        $KeepPlayingRandoms = $true

        while ($KeepPlayingRandoms -and ($LoopRandomCount -lt $MaxRandomPerLoop)) {
            $AllFiles = Get-ChildItem -Path $RandomFolder -File | Where-Object { $_.Extension -match "\.(jpg|jpeg|png|mp4|avi|mov)$" }
            $AvailableFiles = $AllFiles | Where-Object { $PlayedFiles -notcontains $_.FullName }

            if ($AvailableFiles.Count -eq 0) {
                $PlayedFiles = @()
                $AvailableFiles = $AllFiles
            }

            if ($AvailableFiles) {
                $RandomFile = $AvailableFiles | Get-Random
                $PlayedFiles += $RandomFile.FullName
                $syncHash.CurrentPath = $RandomFile.FullName
                
                $syncHash.Media.Dispatcher.Invoke([Action]{
                    $syncHash.Media.Source = [System.Uri]$syncHash.CurrentPath
                    $syncHash.Media.Play()
                })

                $Duration = if ($RandomFile.Extension -match "mp4|avi|mov") { $Time_Video } else { $Time_Graphic }
                Write-Host "Random [$($LoopRandomCount + 1)]: $($RandomFile.Name) ($Duration s)"
                Start-Sleep -Seconds $Duration
                
                $LoopRandomCount++

                # Roll for next random
                $Roll = Get-Random -Minimum 0.0 -Maximum 1.0
                if ($Roll -gt $RandomTargetValue) {
                    $KeepPlayingRandoms = $false
                    Write-Host "Probability check failed ($Roll > $RandomTargetValue). Returning to defaults."
                }
            } else { $KeepPlayingRandoms = $false }
        }
        Start-Sleep -Seconds 1
    }
}
finally {
    if ($syncHash.Media) { $syncHash.Media.Dispatcher.Invoke([Action]{ $syncHash.Window.Close() }) }
    $newRunspace.Close(); $powershell.Dispose()
}