param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$FilePaths
)

function Format-Timestamp ($TotalSeconds) {
    $ts = [TimeSpan]::FromSeconds($TotalSeconds)
    return $ts.ToString("hh\:mm\:ss")
}

function Get-BaseTimestamp ($BaseFile) {
    $basename = [System.IO.Path]::GetFileName($BaseFile)
    
    & ".\insvtools.exe" "dump-meta" $BaseFile 2>&1 | Out-Null
    
    $jsonFiles = Get-ChildItem -Path . -Filter "$basename*.json" -ErrorAction SilentlyContinue
    if (-not $jsonFiles) { return $null }
    
    $jsonFile = $jsonFiles[0].FullName
    $baseTs = $null
    
    try {
        $content = Get-Content $jsonFile -Raw -Encoding UTF8
        
        # PRIMARY ATTEMPT: Look for standard Insta360 metadata
        if ($content -match '"FirstFrameTimestamp"\s*:\s*"?(\d+)"?') {
            $baseTs = [int64]$matches[1]
        } 
        # SECONDARY ATTEMPT: Fallback to frame-by-frame telemetry logs
        elseif ($content -match '"timestamp"\s*:\s*"?(\d+)"?') {
            $baseTs = [int64]$matches[1]
        }
    } finally {
        Remove-Item $jsonFile -Force -ErrorAction SilentlyContinue
    }
    
    return $baseTs
}

function Get-ChainMarkers ($SequenceFiles, $BaseTs) {
    $markers = @()
    
    foreach ($file in $SequenceFiles) {
        $basename = [System.IO.Path]::GetFileName($file)
        
        & ".\insvtools.exe" "decompose-meta" "--frame-type=10" $file 2>&1 | Out-Null
        
        $metaFiles = Get-ChildItem -Path . -Filter "$basename*.type10.meta" -ErrorAction SilentlyContinue
        if (-not $metaFiles) { continue }
        
        $metaFile = $metaFiles[0].FullName
        try {
            $bytes = [System.IO.File]::ReadAllBytes($metaFile)
            
            if ($bytes.Length -ge 5) {
                $numMarkers = [BitConverter]::ToUInt32($bytes, 1)
                $offset = 5
                for ($i = 0; $i -lt $numMarkers; $i++) {
                    $ts = [BitConverter]::ToUInt32($bytes, $offset)
                    $totalSec = ($ts - $BaseTs) / 1000000.0
                    $markers += $totalSec
                    $offset += 8
                }
            }
        } finally {
            Remove-Item $metaFile -Force -ErrorAction SilentlyContinue
        }
    }
    return $markers
}

Write-Host "=================================================="
Write-Host "        Insv Marker Extractor"
Write-Host "=================================================="

if ($FilePaths.Count -eq 0) {
    Write-Host "`n[!] NO FILES DETECTED."
    Write-Host "`nHOW TO USE:"
    Write-Host "1. Do not double-click this shortcut."
    Write-Host "2. Select your .insv files, .lrv files, or a folder."
    Write-Host "3. Drag and drop them directly onto this icon."
    Write-Host "`n=================================================="
    Read-Host "Press Enter to exit..."
    exit
}

$expandedPaths = @()
foreach ($path in $FilePaths) {
    if (Test-Path $path -PathType Container) {
        $expandedPaths += Get-ChildItem -Path $path -Filter "*.insv" -File | Select-Object -ExpandProperty FullName
        $expandedPaths += Get-ChildItem -Path $path -Filter "*.lrv" -File | Select-Object -ExpandProperty FullName
    } elseif (Test-Path $path -PathType Leaf) {
        $expandedPaths += $path
    }
}

if ($expandedPaths.Count -eq 0) {
    Write-Host "`n[!] No valid video files found."
    Write-Host "`n=================================================="
    Read-Host "Press Enter to exit..."
    exit
}

# Pre-scan to group files into unique sequences for accurate progress tracking
$uniqueSessions = @{}
foreach ($path in $expandedPaths) {
    $basename = [System.IO.Path]::GetFileName($path)
    if ($basename -match '(\d{8}_\d{6})') {
        $sessionId = $matches[1]
        $videoDir = [System.IO.Path]::GetDirectoryName($path)
        if ([string]::IsNullOrEmpty($videoDir)) { $videoDir = "." }
        
        if (-not $uniqueSessions.ContainsKey($sessionId)) {
            $uniqueSessions[$sessionId] = $videoDir
        }
    }
}

$totalSessions = $uniqueSessions.Count
$currentSessionIndex = 0

$noMarkerSequences = 0
$noMarkerFiles = 0

foreach ($sessionId in $uniqueSessions.Keys) {
    $currentSessionIndex++
    $videoDir = $uniqueSessions[$sessionId]
    
    # Render native PowerShell progress bar
    $percent = [math]::Round((($currentSessionIndex / $totalSessions) * 100), 0)
    Write-Progress -Activity "Analyzing sequences" -Status "Processing: $sessionId ($currentSessionIndex / $totalSessions)" -PercentComplete $percent
    
    $sequenceFiles = @(Get-ChildItem -Path $videoDir -Filter "VID_$sessionId*.insv" -File | Select-Object -ExpandProperty FullName | Sort-Object)
    $prefix = "VID"
    
    if ($sequenceFiles.Count -eq 0) {
        $sequenceFiles = @(Get-ChildItem -Path $videoDir -Filter "LRV_$sessionId*.lrv" -File | Select-Object -ExpandProperty FullName | Sort-Object)
        $prefix = "LRV"
    }
    
    if ($sequenceFiles.Count -eq 0) { continue }
    
    $baseFile = $sequenceFiles[0]
    $baseTs = Get-BaseTimestamp -BaseFile $baseFile
    
    if ($null -eq $baseTs) {
        Write-Host "`nSequence: ${prefix}_${sessionId}"
        Write-Host ("-" * 40)
        Write-Host "Error: Base timestamp extraction failed."
        continue
    }
    
    $markers = Get-ChainMarkers -SequenceFiles $sequenceFiles -BaseTs $baseTs
    
    if ($markers.Count -eq 0) {
        $noMarkerSequences++
        $noMarkerFiles += $sequenceFiles.Count
    } else {
        Write-Host "`nSequence: ${prefix}_${sessionId} ($($sequenceFiles.Count) files)"
        Write-Host ("-" * 40)
        
        $uniqueMarkers = $markers | ForEach-Object { [math]::Round($_, 2) } | Select-Object -Unique | Sort-Object
        $idx = 1
        foreach ($sec in $uniqueMarkers) {
            $fmt = Format-Timestamp -TotalSeconds $sec
            Write-Host ("Marker {0:D2} : {1}" -f $idx, $fmt)
            $idx++
        }
    }
}

# Clear the progress bar from the screen
Write-Progress -Activity "Analyzing sequences" -Completed

if ($noMarkerSequences -gt 0) {
    Write-Host "`n[i] No markers found in $noMarkerSequences sequence(s) (Total: $noMarkerFiles files)."
}

Write-Host "`n=================================================="
Read-Host "Process completed. Press Enter to exit..."