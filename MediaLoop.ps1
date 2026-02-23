# INSTRUCTIONS FOR EXECUTION:
# 1) Set Execution Policy: Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
# 2) Command to Start: .\MediaLoop.ps1

Add-Type -AssemblyName PresentationFramework, WindowsBase

# --- CONTROL VARIABLES ---
# Base directory (Relative to script location)
$BaseDir = $PSScriptRoot

# Opening Sequence: Add/Remove folders and set their specific display durations
$OpeningSequence = @(
    @{ Folder = "$BaseDir\Opening1"; Duration = 5 }, # AIFair flyer
    @{ Folder = "$BaseDir\Opening2"; Duration = 5 }, # BHT logos
    @{ Folder = "$BaseDir\Opening3"; Duration = 5 }  # Blooper splash
)

# Random Media Settings
$RandomFolder        = "$BaseDir\RandomMedia"
$Time_Graphic_Min    = 1    # Minimum duration for static random images
$Time_Graphic_Max    = 5    # Maximum duration for static random images
$Time_Video          = 9    # Fixed duration for random videos
$MinRandomPerLoop    = 3    # Guaranteed minimum randoms per cycle
$MaxRandomPerLoop    = 7    # Absolute maximum randoms per cycle
$RandomTargetValue   = 0.6  # Probability (0.0 to 1.0) to play another random media

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

# History Tracking
$FolderHistory = @{}

Start-Sleep -Seconds 2

try {
    while ($true) {
        # 1. PLAY OPENING SEQUENCE
        foreach ($Entry in $OpeningSequence) {
            $Path = $Entry.Folder
            if (Test-Path $Path) {
                $AllFiles = Get-ChildItem -Path $Path -File | Where-Object { $_.Extension -match "\.(jpg|jpeg|png|mp4|avi|mov)$" }
                
                if ($AllFiles) {
                    if (-not $FolderHistory.ContainsKey($Path)) { $FolderHistory[$Path] = @() }
                    $Available = $AllFiles | Where-Object { $FolderHistory[$Path] -notcontains $_.FullName }

                    if ($Available.Count -eq 0) {
                        $FolderHistory[$Path] = @()
                        $Available = $AllFiles
                    }

                    $SelectedFile = $Available | Get-Random
                    $FolderHistory[$Path] += $SelectedFile.FullName

                    Write-Host "Opening Loop: $($SelectedFile.Name) from $Path ($($Entry.Duration)s)"
                    
                    $syncHash.CurrentPath = $SelectedFile.FullName
                    $syncHash.Media.Dispatcher.Invoke([Action]{
                        $syncHash.Media.Source = [System.Uri]$syncHash.CurrentPath
                        $syncHash.Media.Play()
                    })
                    Start-Sleep -Seconds $Entry.Duration
                }
            }
        }

        # 2. PLAY RANDOM MEDIA (MINIMUM GUARANTEE + PROBABILISTIC)
        $LoopRandomCount = 0
        $KeepPlayingRandoms = $true
        
        if (-not $FolderHistory.ContainsKey($RandomFolder)) { $FolderHistory[$RandomFolder] = @() }

        while ($KeepPlayingRandoms -and ($LoopRandomCount -lt $MaxRandomPerLoop)) {
            $AllRandom = Get-ChildItem -Path $RandomFolder -File | Where-Object { $_.Extension -match "\.(jpg|jpeg|png|mp4|avi|mov)$" }
            $AvailableRandom = $AllRandom | Where-Object { $FolderHistory[$RandomFolder] -notcontains $_.FullName }

            if ($AvailableRandom.Count -eq 0) {
                $FolderHistory[$RandomFolder] = @()
                $AvailableRandom = $AllRandom
            }

            if ($AvailableRandom) {
                $RandomFile = $AvailableRandom | Get-Random
                $FolderHistory[$RandomFolder] += $RandomFile.FullName
                $syncHash.CurrentPath = $RandomFile.FullName
                
                $syncHash.Media.Dispatcher.Invoke([Action]{
                    $syncHash.Media.Source = [System.Uri]$syncHash.CurrentPath
                    $syncHash.Media.Play()
                })

                # Determine Duration: Random range for graphics, fixed for video
                if ($RandomFile.Extension -match "mp4|avi|mov") {
                    $Duration = $Time_Video
                    Write-Host "Random [$($LoopRandomCount + 1)]: $($RandomFile.Name) (Video: $Duration s)"
                } else {
                    $Duration = Get-Random -Minimum $Time_Graphic_Min -Maximum ($Time_Graphic_Max + 1)
                    Write-Host "Random [$($LoopRandomCount + 1)]: $($RandomFile.Name) (Graphic: $Duration s)"
                }

                Start-Sleep -Seconds $Duration
                $LoopRandomCount++

                # Check minimum requirement before attempting to roll for exit
                if ($LoopRandomCount -lt $MinRandomPerLoop) { 
                    Write-Host "Minimum not met ($LoopRandomCount/$MinRandomPerLoop). Continuing..."
                    continue 
                }

                # Probability Roll
                $Roll = Get-Random -Minimum 0.0 -Maximum 1.0
                if ($Roll -gt $RandomTargetValue) {
                    $KeepPlayingRandoms = $false
                    Write-Host "Roll failed ($Roll > $RandomTargetValue). Returning to Openings."
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