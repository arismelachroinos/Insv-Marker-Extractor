param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$FilePaths
)

function Format-Timestamp ($TotalSeconds) {
    $ts = [TimeSpan]::FromSeconds($TotalSeconds)
    return $ts.ToString("hh\:mm\:ss")
}

function Get-LerpValue ($t, $t0, $t1, $v0, $v1) {
    if ($t1 -eq $t0) { return [double]$v0 }
    $factor = ([double]$t - [double]$t0) / ([double]$t1 - [double]$t0)
    return [double]$v0 + $factor * ([double]$v1 - [double]$v0)
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
        if ($content -match '"FirstFrameTimestamp"\s*:\s*"?(\d+)"?') {
            $baseTs = [int64]$matches[1]
        } elseif ($content -match '"timestamp"\s*:\s*"?(\d+)"?') {
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

function Inject-StudioKeyframes ($SessionId, $UniqueMarkerSeconds) {
    # Dynamically locate the Footage Project directory via startup.ini
    $localAppData = [System.Environment]::GetFolderPath('LocalApplicationData')
    $startupIniPath = Join-Path $localAppData "Insta360\Insta360 Studio\startup.ini"
    $footageProjectsDir = $null
    
    if (Test-Path $startupIniPath -PathType Leaf) {
        $iniContent = Get-Content $startupIniPath -ErrorAction SilentlyContinue
        foreach ($line in $iniContent) {
            if ($line -match "^\s*footage_project_location\s*=\s*(.+)$") {
                $extractedPath = $matches[1].Trim()
                $extractedPath = $extractedPath -replace '/', '\' # Normalize slashes for Windows
                if (Test-Path $extractedPath -PathType Container) {
                    $footageProjectsDir = $extractedPath
                }
                break
            }
        }
    }
    
    # Fallback to the default Documents location if ini parsing fails or the custom directory was deleted
    if ([string]::IsNullOrEmpty($footageProjectsDir)) {
        $docsPath = [System.Environment]::GetFolderPath('MyDocuments')
        $footageProjectsDir = Join-Path $docsPath "Insta360\Studio\FootageProject"
    }
    
    if (-not (Test-Path $footageProjectsDir)) {
        return "Studio projects directory not found at: $footageProjectsDir"
    }
    
    $projectFiles = Get-ChildItem -Path $footageProjectsDir -Filter "footage_project.insprj" -Recurse -File -ErrorAction SilentlyContinue
    if (-not $projectFiles) {
        return "No Studio project files found in directory."
    }
    
    $targetProject = $null
    foreach ($p in $projectFiles) {
        $rawText = Get-Content -Path $p.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($rawText -and ($rawText -match $SessionId)) {
            $targetProject = $p.FullName
            break
        }
    }
    
    if (-not $targetProject) {
        return "Project not found in Studio. (Open clip in Insta360 Studio first)."
    }
    
    try {
        $jsonContent = Get-Content -Path $targetProject -Raw -Encoding UTF8
        $projData = $jsonContent | ConvertFrom-Json
        
        if (-not $projData.projects -or $projData.projects.Count -eq 0 -or -not $projData.projects[0].clip) {
            return "Corrupted or invalid project structure."
        }
        
        $clip = $projData.projects[0].clip
        $fps = if ($clip.fps -and [double]$clip.fps -gt 0) { [double]$clip.fps } else { 29.97002997 }
        
        $existingNodes = @()
        if ($clip.key_frame_track -and $clip.key_frame_track.node_list) {
            $existingNodes = @($clip.key_frame_track.node_list | Where-Object { $_.node_type -eq 0 } | Sort-Object time)
        }
        
        $finalKeyframes = [System.Collections.Generic.List[PSObject]]::new()
        foreach ($node in $existingNodes) {
            $finalKeyframes.Add($node)
        }
        
        $defaultDistance = 0.949999988079071
        $defaultFov = 1.3952149152755737
        if ($clip.camera_transform) {
            if ($clip.camera_transform.distance) { $defaultDistance = [double]$clip.camera_transform.distance }
            if ($clip.camera_transform.fov -and $clip.camera_transform.fov.value) { $defaultFov = [double]$clip.camera_transform.fov.value }
        }
        
        foreach ($sec in $UniqueMarkerSeconds) {
            $frameNum = [int64][math]::Round($sec * $fps)
            
            $exactMatch = $finalKeyframes | Where-Object { $_.time -eq $frameNum }
            if ($exactMatch) { continue }
            
            $newNode = [PSCustomObject]@{
                auto_fov      = 0
                distance      = $defaultDistance
                fov           = $defaultFov
                is_headtrack  = 0
                name          = [guid]::NewGuid().ToString().ToLower()
                node_type     = 0
                pan           = 0
                roll          = 0
                src_time      = $frameNum
                state         = 7
                tilt          = 0
                time          = $frameNum
            }
            
            if ($existingNodes.Count -eq 1) {
                $ref = $existingNodes[0]
                $newNode.pan = [double]$ref.pan; $newNode.tilt = [double]$ref.tilt; $newNode.roll = [double]$ref.roll
                $newNode.fov = [double]$ref.fov; $newNode.distance = [double]$ref.distance
            } 
            elseif ($existingNodes.Count -gt 1) {
                $leftNodes = $existingNodes | Where-Object { $_.time -lt $frameNum } | Sort-Object time -Descending
                $rightNodes = $existingNodes | Where-Object { $_.time -gt $frameNum } | Sort-Object time
                
                if ($leftNodes -and $rightNodes) {
                    $L = $leftNodes[0]
                    $R = $rightNodes[0]
                    $newNode.pan = Get-LerpValue $frameNum $L.time $R.time $L.pan $R.pan
                    $newNode.tilt = Get-LerpValue $frameNum $L.time $R.time $L.tilt $R.tilt
                    $newNode.roll = Get-LerpValue $frameNum $L.time $R.time $L.roll $R.roll
                    $newNode.fov = Get-LerpValue $frameNum $L.time $R.time $L.fov $R.fov
                    $newNode.distance = Get-LerpValue $frameNum $L.time $R.time $L.distance $R.distance
                }
                elseif ($leftNodes -and -not $rightNodes) {
                    $ref = $leftNodes[0]
                    $newNode.pan = [double]$ref.pan; $newNode.tilt = [double]$ref.tilt; $newNode.roll = [double]$ref.roll
                    $newNode.fov = [double]$ref.fov; $newNode.distance = [double]$ref.distance
                }
                elseif (-not $leftNodes -and $rightNodes) {
                    $ref = $rightNodes[0]
                    $newNode.pan = [double]$ref.pan; $newNode.tilt = [double]$ref.tilt; $newNode.roll = [double]$ref.roll
                    $newNode.fov = [double]$ref.fov; $newNode.distance = [double]$ref.distance
                }
            }
            
            $finalKeyframes.Add($newNode)
        }
        
        $sortedNodes = $finalKeyframes | Sort-Object time
        $rebuiltList = [System.Collections.Generic.List[PSObject]]::new()
        $prevNode = $null
        
        foreach ($node in $sortedNodes) {
            if ($null -ne $prevNode) {
                $transNode = [PSCustomObject]@{
                    name      = "$($prevNode.name)-$($node.name)"
                    node_type = 1
                    point1X   = 0.5
                    point1Y   = 0.5
                    point2X   = 0.5
                    point2Y   = 0.5
                    type      = 1
                }
                $rebuiltList.Add($transNode)
            }
            $rebuiltList.Add($node)
            $prevNode = $node
        }
        
        $clip.enable_user_keyframe = $true
        if (-not $clip.key_frame_track) {
            $clip | Add-Member -MemberType NoteProperty -Name "key_frame_track" -Value ([PSCustomObject]@{}) -Force
        }
        $clip.key_frame_track | Add-Member -MemberType NoteProperty -Name "node_list" -Value ($rebuiltList.ToArray()) -Force
        
        Copy-Item -Path $targetProject -Destination "$targetProject.bak" -Force
        
        $updatedJson = $projData | ConvertTo-Json -Depth 32
        [System.IO.File]::WriteAllText($targetProject, $updatedJson, [System.Text.Encoding]::UTF8)
        
        return "SUCCESS"
    } catch {
        return "Failed to inject keyframes: $($_.Exception.Message)"
    }
}

Write-Host "=================================================="
Write-Host "             Insv Marker Extractor"
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
        
        $injectResult = Inject-StudioKeyframes -SessionId $sessionId -UniqueMarkerSeconds $uniqueMarkers
        if ($injectResult -eq "SUCCESS") {
            Write-Host "[+] Injected $($uniqueMarkers.Count) keyframe(s) into Insta360 Studio project." -ForegroundColor Green
        } else {
            Write-Host "[i] Studio Project: $injectResult" -ForegroundColor DarkGray
        }
    }
}

Write-Progress -Activity "Analyzing sequences" -Completed

if ($noMarkerSequences -gt 0) {
    Write-Host "`n[i] No markers found in $noMarkerSequences sequence(s) (Total: $noMarkerFiles files)."
}

Write-Host "`n=================================================="
Read-Host "Process completed. Press Enter to exit..."