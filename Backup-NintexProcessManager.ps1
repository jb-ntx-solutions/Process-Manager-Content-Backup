<#
.SYNOPSIS
    Backs up Nintex Process Manager content to local files.

.DESCRIPTION
    This script exports processes and documents from a Nintex Process Manager site.
    Three export modes are available:
    - XMLExport: Exports processes as XML files
    - ProcessPrint: Exports processes as PDF files
    - ProcessPrintAndDocuments: Exports processes as PDF files and includes linked documents

.PARAMETER Mode
    The export mode: XMLExport, ProcessPrint, or ProcessPrintAndDocuments

.EXAMPLE
    .\Backup-NintexProcessManager.ps1 -Mode XMLExport

.EXAMPLE
    .\Backup-NintexProcessManager.ps1 -Mode ProcessPrint

.NOTES
    Author: Nintex
    Date: 2025-12-08
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("XMLExport", "ProcessPrint", "ProcessPrintAndDocuments")]
    [string]$Mode
)

#region Helper Functions

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Level = "Info"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "Info" { "Cyan" }
        "Success" { "Green" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
    }

    Write-Host "[$timestamp] " -NoNewline
    Write-Host "$Message" -ForegroundColor $color
}

function Format-ElapsedTime {
    param([TimeSpan]$TimeSpan)

    if ($TimeSpan.TotalHours -ge 1) {
        return "{0:D2}h {1:D2}m {2:D2}s" -f $TimeSpan.Hours, $TimeSpan.Minutes, $TimeSpan.Seconds
    }
    elseif ($TimeSpan.TotalMinutes -ge 1) {
        return "{0:D2}m {2:D2}s" -f $TimeSpan.Hours, $TimeSpan.Minutes, $TimeSpan.Seconds
    }
    else {
        return "{0:D2}s" -f $TimeSpan.Seconds
    }
}

function Get-SafeFileName {
    param([string]$FileName)

    $invalidChars = [IO.Path]::GetInvalidFileNameChars() -join ''
    $sanitized = $FileName -replace "[$invalidChars]", '_'
    $sanitized = $sanitized -replace '\s+', ' '
    $sanitized = $sanitized.Trim()

    # Limit length to avoid path issues
    if ($sanitized.Length -gt 200) {
        $sanitized = $sanitized.Substring(0, 200)
    }

    return $sanitized
}

function Get-AuthToken {
    param(
        [string]$SiteUrl,
        [string]$Username,
        [string]$Password
    )

    Write-Log "Authenticating to $SiteUrl..." -Level Info

    # Extract tenant ID from site URL
    $uri = [System.Uri]$SiteUrl
    $pathSegments = $uri.AbsolutePath.Trim('/').Split('/')
    $tenantId = $pathSegments[0]

    $tokenUrl = "$($uri.Scheme)://$($uri.Host)/$tenantId/oauth2/token"

    $body = @{
        grant_type = "password"
        username = $Username
        password = $Password
        duration = "60000"
    }

    try {
        $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
        Write-Log "Authentication successful" -Level Success
        return $response.access_token
    }
    catch {
        Write-Log "Authentication failed: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Get-ProcessGroups {
    param(
        [string]$SiteUrl,
        [string]$Token,
        [string]$ParentUniqueId = $null
    )

    $uri = [System.Uri]$SiteUrl
    $pathSegments = $uri.AbsolutePath.Trim('/').Split('/')
    $tenantId = $pathSegments[0]

    $endpoint = "$($uri.Scheme)://$($uri.Host)/$tenantId/Process/View/GetChildProcessGroupTreeItems"

    if ($ParentUniqueId) {
        $endpoint += "?uniqueId=$ParentUniqueId"
    }

    $headers = @{
        Authorization = "Bearer $Token"
    }

    try {
        $response = Invoke-RestMethod -Uri $endpoint -Method Get -Headers $headers
        return $response.treeItems
    }
    catch {
        Write-Log "Failed to get process groups: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Get-AllProcessGroupsRecursive {
    param(
        [string]$SiteUrl,
        [string]$Token
    )

    Write-Log "Retrieving process group hierarchy..." -Level Info

    $allGroups = @()
    $processedGroupIds = @{}  # Track processed groups by UniqueId
    $queuedGroupIds = @{}     # Track groups already queued to prevent duplicate API calls
    $groupsToProcess = @(@{ UniqueId = $null; Path = "" })
    $groupsProcessed = 0

    while ($groupsToProcess.Count -gt 0) {
        $current = $groupsToProcess[0]
        $groupsToProcess = $groupsToProcess[1..($groupsToProcess.Count - 1)]

        $groups = Get-ProcessGroups -SiteUrl $SiteUrl -Token $Token -ParentUniqueId $current.UniqueId
        $groupsProcessed++

        foreach ($group in $groups) {
            if ($group.itemType -eq "group") {
                # Check if we've already processed this group by its UniqueId
                if ($processedGroupIds.ContainsKey($group.uniqueId)) {
                    Write-Verbose "Skipping duplicate group: $($group.title) (UniqueId: $($group.uniqueId))"
                    continue
                }

                $groupPath = if ($current.Path) { "$($current.Path)\$($group.title)" } else { $group.title }

                $groupInfo = [PSCustomObject]@{
                    Id = $group.id
                    UniqueId = $group.uniqueId
                    Title = $group.title
                    Path = $groupPath
                    HasChild = $group.hasChild
                }

                $allGroups += $groupInfo
                $processedGroupIds[$group.uniqueId] = $true

                # Only queue groups that have children AND haven't been queued yet
                if ($group.hasChild -and -not $queuedGroupIds.ContainsKey($group.uniqueId)) {
                    $groupsToProcess += @{ UniqueId = $group.uniqueId; Path = $groupPath }
                    $queuedGroupIds[$group.uniqueId] = $true
                    Write-Verbose "Queued group for child processing: $($group.title) (UniqueId: $($group.uniqueId))"
                }
                elseif ($group.hasChild -and $queuedGroupIds.ContainsKey($group.uniqueId)) {
                    Write-Verbose "Skipping already queued group: $($group.title) (UniqueId: $($group.uniqueId))"
                }
            }
        }

        # Show progress update every few groups
        if ($groupsProcessed % 5 -eq 0 -or $groupsToProcess.Count -eq 0) {
            Write-Host "`r  > Discovered $($allGroups.Count) unique groups ($groupsProcessed API calls, $($groupsToProcess.Count) remaining)..." -NoNewline -ForegroundColor Gray
        }
    }

    Write-Host "`r" -NoNewline  # Clear the progress line
    Write-Log "Found $($allGroups.Count) unique process groups ($groupsProcessed API calls)" -Level Success
    return $allGroups
}

function Get-AllProcesses {
    param(
        [string]$SiteUrl,
        [string]$Token,
        [bool]$IncludeArchived
    )

    Write-Log "Retrieving process list..." -Level Info

    $uri = [System.Uri]$SiteUrl
    $pathSegments = $uri.AbsolutePath.Trim('/').Split('/')
    $tenantId = $pathSegments[0]

    $baseEndpoint = "$($uri.Scheme)://$($uri.Host)/$tenantId/Bff/Process/api/v1/processes"

    $headers = @{
        Authorization = "Bearer $Token"
    }

    $allProcesses = @()
    $listTypes = @(0)  # Active processes

    if ($IncludeArchived) {
        $listTypes += 7  # Archived processes
    }

    foreach ($listType in $listTypes) {
        $page = 1
        $pageSize = 100
        $totalProcessed = 0

        do {
            $endpoint = "$baseEndpoint?Page=$page&PageSize=$pageSize&Listtype=$listType"

            try {
                $response = Invoke-RestMethod -Uri $endpoint -Method Get -Headers $headers

                $allProcesses += $response.items
                $totalProcessed += $response.items.Count

                $statusType = if ($listType -eq 0) { "active" } else { "archived" }
                Write-Log "Retrieved $totalProcessed of $($response.totalItemCount) $statusType processes..." -Level Info

                $page++
            }
            catch {
                Write-Log "Failed to get processes (Page $page): $($_.Exception.Message)" -Level Error
                throw
            }
        } while ($totalProcessed -lt $response.totalItemCount)
    }

    Write-Log "Retrieved total of $($allProcesses.Count) processes" -Level Success
    return $allProcesses
}

function Export-ProcessAsXML {
    param(
        [string]$SiteUrl,
        [string]$Token,
        [string]$ProcessUniqueId,
        [string]$OutputPath
    )

    $uri = [System.Uri]$SiteUrl
    $pathSegments = $uri.AbsolutePath.Trim('/').Split('/')
    $tenantId = $pathSegments[0]

    $endpoint = "$($uri.Scheme)://$($uri.Host)/$tenantId/Process/ImportExport/ExportProcess/$ProcessUniqueId`?isMinimode=False&latest=True&format=XML"

    $headers = @{
        Authorization = "Bearer $Token"
    }

    try {
        Invoke-RestMethod -Uri $endpoint -Method Get -Headers $headers -OutFile $OutputPath
        return $true
    }
    catch {
        Write-Log "Failed to export XML for process $ProcessUniqueId : $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Export-ProcessAsPDF {
    param(
        [string]$SiteUrl,
        [string]$Token,
        [string]$ProcessUniqueId,
        [string]$OutputPath
    )

    $uri = [System.Uri]$SiteUrl
    $pathSegments = $uri.AbsolutePath.Trim('/').Split('/')
    $tenantId = $pathSegments[0]

    $endpoint = "$($uri.Scheme)://$($uri.Host)/$tenantId/Process/ImportExport/Print?ProcessUniqueId=$ProcessUniqueId&IncludeFlowchart=true&IncludeProcedure=true&IncludeImages=true&IncludeBusinessAnalysis=true&IncludeFullNotes=true&IncludeTimeframes=true&IncludeRiskReference=true&IncludeCosts=true&IsShowIncludeCosts=true&Orientation=Portrait&PaperKind=A4&NoOfColumns=2&Format=PDF&IsMinimode=false&GroupOption=Group&IncludeSubProcesses=false"

    $headers = @{
        Authorization = "Bearer $Token"
    }

    try {
        Invoke-RestMethod -Uri $endpoint -Method Get -Headers $headers -OutFile $OutputPath
        return $true
    }
    catch {
        Write-Log "Failed to export PDF for process $ProcessUniqueId : $($_.Exception.Message)" -Level Error
        return $false
    }
}

function New-GroupFolderStructure {
    param(
        [string]$BaseOutputPath,
        [array]$ProcessGroups
    )

    Write-Log "Creating folder structure..." -Level Info

    $folderMap = @{}

    foreach ($group in $ProcessGroups) {
        $folderPath = Join-Path -Path $BaseOutputPath -ChildPath $group.Path

        if (-not (Test-Path -Path $folderPath)) {
            New-Item -Path $folderPath -ItemType Directory -Force | Out-Null
        }

        $folderMap[$group.UniqueId] = $folderPath
    }

    Write-Log "Folder structure created" -Level Success
    return $folderMap
}

function Get-AllDocuments {
    param(
        [string]$SiteUrl,
        [string]$Token
    )

    Write-Log "Retrieving document list..." -Level Info

    $uri = [System.Uri]$SiteUrl
    $pathSegments = $uri.AbsolutePath.Trim('/').Split('/')
    $tenantId = $pathSegments[0]

    $baseEndpoint = "$($uri.Scheme)://$($uri.Host)/$tenantId/bff/document/api/v1/documents"

    $headers = @{
        Authorization = "Bearer $Token"
    }

    $allDocuments = @()
    $page = 1
    $pageSize = 100
    $totalProcessed = 0

    do {
        $endpoint = "$baseEndpoint`?Page=$page&PageSize=$pageSize&DocumentType=All"

        try {
            $response = Invoke-RestMethod -Uri $endpoint -Method Get -Headers $headers

            $allDocuments += $response.items
            $totalProcessed += $response.items.Count

            Write-Log "Retrieved $totalProcessed of $($response.totalItemCount) documents..." -Level Info

            $page++
        }
        catch {
            Write-Log "Failed to get documents (Page $page): $($_.Exception.Message)" -Level Error
            throw
        }
    } while ($totalProcessed -lt $response.totalItemCount)

    Write-Log "Retrieved total of $($allDocuments.Count) documents" -Level Success
    return $allDocuments
}

function Export-Document {
    param(
        [string]$SiteUrl,
        [string]$Token,
        [string]$DocumentUniqueId,
        [string]$DocumentName,
        [string]$OutputPath
    )

    $uri = [System.Uri]$SiteUrl
    $pathSegments = $uri.AbsolutePath.Trim('/').Split('/')
    $tenantId = $pathSegments[0]

    $endpoint = "$($uri.Scheme)://$($uri.Host)/$tenantId/Documents/View/Open?displayType=document&documentId=$DocumentUniqueId"

    $headers = @{
        Authorization = "Bearer $Token"
    }

    try {
        # Create a temporary file to store the response
        $tempFile = [System.IO.Path]::GetTempFileName()

        # Download the document
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("Authorization", "Bearer $Token")

        try {
            $webClient.DownloadFile($endpoint, $tempFile)
        }
        finally {
            $webClient.Dispose()
        }

        # Read the content to check if it's Base64 encoded
        $content = Get-Content -Path $tempFile -Raw -Encoding UTF8

        # Check if the content appears to be Base64 (text-based)
        if ($content -and $content.Length -gt 0 -and $content -match '^[A-Za-z0-9+/=\s]+$') {
            try {
                # Try to decode as Base64
                $bytes = [System.Convert]::FromBase64String($content.Trim())
                [System.IO.File]::WriteAllBytes($OutputPath, $bytes)
                Remove-Item -Path $tempFile -Force
                return $true
            }
            catch {
                # Not Base64, treat as binary file
                Move-Item -Path $tempFile -Destination $OutputPath -Force
                return $true
            }
        }
        else {
            # Binary file, just move it
            Move-Item -Path $tempFile -Destination $OutputPath -Force
            return $true
        }
    }
    catch {
        Write-Log "Failed to export document $DocumentName : $($_.Exception.Message)" -Level Error

        # Clean up temp file if it exists
        if (Test-Path -Path $tempFile) {
            Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
        }

        return $false
    }
}

#endregion

#region Main Script

function Start-Backup {
    # Display banner
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  Nintex Process Manager Backup Script" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""

    # Get export mode if not provided
    if (-not $Mode) {
        Write-Host "Select export mode:" -ForegroundColor Yellow
        Write-Host "  1. XML Export" -ForegroundColor White
        Write-Host "  2. Process Print (PDF)" -ForegroundColor White
        Write-Host "  3. Process Print and Documents (PDF + Documents)" -ForegroundColor White
        Write-Host ""

        do {
            $selection = Read-Host "Enter selection (1-3)"
        } while ($selection -notin @("1", "2", "3"))

        $Mode = switch ($selection) {
            "1" { "XMLExport" }
            "2" { "ProcessPrint" }
            "3" { "ProcessPrintAndDocuments" }
        }
    }

    Write-Log "Export mode: $Mode" -Level Info
    Write-Host ""

    # Get site URL
    Write-Host "Enter your Process Manager site URL" -ForegroundColor Yellow
    Write-Host "  Example: https://us.promapp.com/siteName" -ForegroundColor Gray
    $siteUrl = Read-Host "Site URL"
    $siteUrl = $siteUrl.TrimEnd('/')

    # Get credentials
    Write-Host ""
    Write-Host "Enter service account credentials" -ForegroundColor Yellow
    $username = Read-Host "Username"
    $securePassword = Read-Host "Password" -AsSecureString
    $password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    )

    # Get output directory
    Write-Host ""
    Write-Host "Enter output directory path" -ForegroundColor Yellow
    $outputPath = Read-Host "Output directory"

    if (-not (Test-Path -Path $outputPath)) {
        Write-Log "Creating output directory: $outputPath" -Level Info
        New-Item -Path $outputPath -ItemType Directory -Force | Out-Null
    }

    # Ask about archived processes
    Write-Host ""
    $includeArchivedResponse = Read-Host "Include archived processes? (Y/N)"
    $includeArchived = $includeArchivedResponse -eq 'Y' -or $includeArchivedResponse -eq 'y'

    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  Starting Backup Process" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""

    # Track overall backup time
    $backupStartTime = Get-Date

    # Authenticate
    $token = Get-AuthToken -SiteUrl $siteUrl -Username $username -Password $password

    # Get process groups
    $processGroups = Get-AllProcessGroupsRecursive -SiteUrl $siteUrl -Token $token

    # Create folder structure
    $folderMap = New-GroupFolderStructure -BaseOutputPath $outputPath -ProcessGroups $processGroups

    # Get all processes
    $processes = Get-AllProcesses -SiteUrl $siteUrl -Token $token -IncludeArchived $includeArchived

    # Export processes
    Write-Log "Starting process export..." -Level Info
    Write-Host ""

    $successCount = 0
    $failureCount = 0
    $totalCount = $processes.Count
    $processStartTime = Get-Date

    for ($i = 0; $i -lt $totalCount; $i++) {
        $process = $processes[$i]
        $currentNum = $i + 1

        # Calculate elapsed time and rate
        $elapsed = (Get-Date) - $processStartTime
        $rate = if ($elapsed.TotalSeconds -gt 0) { [math]::Round($currentNum / $elapsed.TotalSeconds, 2) } else { 0 }
        $elapsedStr = Format-ElapsedTime -TimeSpan $elapsed

        # Estimate time remaining
        $remaining = if ($rate -gt 0) {
            $remainingSeconds = ($totalCount - $currentNum) / $rate
            Format-ElapsedTime -TimeSpan ([TimeSpan]::FromSeconds($remainingSeconds))
        } else {
            "calculating..."
        }

        $statusMessage = "Processing $currentNum of $totalCount | Elapsed: $elapsedStr | Rate: $rate/sec | ETA: $remaining | Current: $($process.processName)"
        Write-Progress -Activity "Exporting Processes" -Status $statusMessage -PercentComplete (($currentNum / $totalCount) * 100)

        # Determine output folder
        $outputFolder = $folderMap[$process.groupUniqueId]

        if (-not $outputFolder) {
            # Group not found in our hierarchy, use a default "Ungrouped" folder
            $outputFolder = Join-Path -Path $outputPath -ChildPath "_Ungrouped"
            if (-not (Test-Path -Path $outputFolder)) {
                New-Item -Path $outputFolder -ItemType Directory -Force | Out-Null
            }
        }

        # Sanitize process name for filename
        $safeFileName = Get-SafeFileName -FileName $process.processName

        # Export based on mode
        $success = $false

        if ($Mode -eq "XMLExport") {
            $filePath = Join-Path -Path $outputFolder -ChildPath "$safeFileName.xml"
            $success = Export-ProcessAsXML -SiteUrl $siteUrl -Token $token -ProcessUniqueId $process.processUniqueId -OutputPath $filePath
        }
        else {
            # ProcessPrint or ProcessPrintAndDocuments
            $filePath = Join-Path -Path $outputFolder -ChildPath "$safeFileName.pdf"
            $success = Export-ProcessAsPDF -SiteUrl $siteUrl -Token $token -ProcessUniqueId $process.processUniqueId -OutputPath $filePath
        }

        if ($success) {
            $successCount++
            # Only log every 10th success to reduce console spam
            if ($currentNum % 10 -eq 0 -or $currentNum -eq $totalCount) {
                Write-Log "[$currentNum/$totalCount] Exported $successCount processes so far... (latest: $($process.processName))" -Level Success
            }
        }
        else {
            $failureCount++
        }

        # Brief pause to avoid overwhelming the server
        Start-Sleep -Milliseconds 100
    }

    Write-Progress -Activity "Exporting Processes" -Completed
    $processElapsed = (Get-Date) - $processStartTime
    Write-Log "Process export completed in $(Format-ElapsedTime -TimeSpan $processElapsed)" -Level Info

    # Export documents if in ProcessPrintAndDocuments mode
    $docSuccessCount = 0
    $docFailureCount = 0
    $docTotalCount = 0

    if ($Mode -eq "ProcessPrintAndDocuments") {
        Write-Host ""
        Write-Host "================================================" -ForegroundColor Cyan
        Write-Host "  Starting Document Export" -ForegroundColor Cyan
        Write-Host "================================================" -ForegroundColor Cyan
        Write-Host ""

        # Get all documents
        $documents = Get-AllDocuments -SiteUrl $siteUrl -Token $token
        $docTotalCount = $documents.Count

        Write-Log "Starting document export..." -Level Info
        Write-Host ""

        $docStartTime = Get-Date

        for ($i = 0; $i -lt $docTotalCount; $i++) {
            $document = $documents[$i]
            $currentNum = $i + 1

            # Calculate elapsed time and rate
            $docElapsed = (Get-Date) - $docStartTime
            $docRate = if ($docElapsed.TotalSeconds -gt 0) { [math]::Round($currentNum / $docElapsed.TotalSeconds, 2) } else { 0 }
            $docElapsedStr = Format-ElapsedTime -TimeSpan $docElapsed

            # Estimate time remaining
            $docRemaining = if ($docRate -gt 0) {
                $remainingSeconds = ($docTotalCount - $currentNum) / $docRate
                Format-ElapsedTime -TimeSpan ([TimeSpan]::FromSeconds($remainingSeconds))
            } else {
                "calculating..."
            }

            $docStatusMessage = "Processing $currentNum of $docTotalCount | Elapsed: $docElapsedStr | Rate: $docRate/sec | ETA: $docRemaining | Current: $($document.documentName)"
            Write-Progress -Activity "Exporting Documents" -Status $docStatusMessage -PercentComplete (($currentNum / $docTotalCount) * 100)

            # Determine output folder based on primary group
            $outputFolder = $folderMap[$document.primaryGroupUniqueId]

            if (-not $outputFolder) {
                # Group not found in our hierarchy, use a default "Ungrouped" folder
                $outputFolder = Join-Path -Path $outputPath -ChildPath "_Ungrouped"
                if (-not (Test-Path -Path $outputFolder)) {
                    New-Item -Path $outputFolder -ItemType Directory -Force | Out-Null
                }
            }

            # Create a Documents subfolder within the group folder
            $documentsFolder = Join-Path -Path $outputFolder -ChildPath "_Documents"
            if (-not (Test-Path -Path $documentsFolder)) {
                New-Item -Path $documentsFolder -ItemType Directory -Force | Out-Null
            }

            # Sanitize document name for filename
            $safeFileName = Get-SafeFileName -FileName $document.documentName

            $filePath = Join-Path -Path $documentsFolder -ChildPath $safeFileName

            # Export document
            $docSuccess = Export-Document -SiteUrl $siteUrl -Token $token -DocumentUniqueId $document.documentUniqueId -DocumentName $document.documentName -OutputPath $filePath

            if ($docSuccess) {
                $docSuccessCount++
                # Only log every 10th success to reduce console spam
                if ($currentNum % 10 -eq 0 -or $currentNum -eq $docTotalCount) {
                    Write-Log "[$currentNum/$docTotalCount] Exported $docSuccessCount documents so far... (latest: $($document.documentName))" -Level Success
                }
            }
            else {
                $docFailureCount++
            }

            # Brief pause to avoid overwhelming the server
            Start-Sleep -Milliseconds 100
        }

        Write-Progress -Activity "Exporting Documents" -Completed
        $docTotalElapsed = (Get-Date) - $docStartTime
        Write-Log "Document export completed in $(Format-ElapsedTime -TimeSpan $docTotalElapsed)" -Level Info
    }

    # Summary
    $totalBackupTime = (Get-Date) - $backupStartTime
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  Backup Complete" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Log "Total backup time: $(Format-ElapsedTime -TimeSpan $totalBackupTime)" -Level Info
    Write-Host ""
    Write-Log "Total processes: $totalCount" -Level Info
    Write-Log "Successfully exported: $successCount" -Level Success

    if ($failureCount -gt 0) {
        Write-Log "Failed process exports: $failureCount" -Level Warning
    }

    if ($Mode -eq "ProcessPrintAndDocuments") {
        Write-Host ""
        Write-Log "Total documents: $docTotalCount" -Level Info
        Write-Log "Successfully exported: $docSuccessCount" -Level Success

        if ($docFailureCount -gt 0) {
            Write-Log "Failed document exports: $docFailureCount" -Level Warning
        }
    }

    Write-Host ""
    Write-Log "Backup saved to: $outputPath" -Level Info
    Write-Host ""
}

# Execute main script with error handling
try {
    Start-Backup
}
catch {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Red
    Write-Host "  Script Error" -ForegroundColor Red
    Write-Host "================================================" -ForegroundColor Red
    Write-Host ""
    Write-Log "An unexpected error occurred: $($_.Exception.Message)" -Level Error
    Write-Host ""
    Write-Host "Error Details:" -ForegroundColor Red
    Write-Host $_.Exception.ToString() -ForegroundColor Red
    Write-Host ""
}
finally {
    # Wait for user input before closing
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

#endregion
