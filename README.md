# Nintex Process Manager Content Backup Script

A PowerShell script to backup and export content from Nintex Process Manager sites locally.

## Overview

This script connects to a Nintex Process Manager site and exports all processes (and optionally documents) to a local folder structure that mirrors the Process Manager group hierarchy.

## Features

- **Three Export Modes:**
  - **XML Export**: Exports all processes as XML files
  - **Process Print**: Exports all processes as PDF files
  - **Process Print and Documents**: Exports processes as PDF files and includes all documents from the site

- **Comprehensive Backup:**
  - Retrieves complete process group hierarchy
  - Creates matching folder structure locally
  - Handles pagination for large process lists (processes and documents)
  - Optional inclusion of archived processes
  - **Enhanced progress tracking** with real-time status updates:
    - Elapsed time tracking for overall backup and individual phases
    - Processing rate (items/second) for processes and documents
    - Estimated time remaining (ETA) calculations
    - Live status updates showing current item being processed
    - Periodic progress logs to prevent console spam
  - Automatic Base64 decoding for documents
  - Documents organized in _Documents subfolders within their primary groups
  - Detailed logging with timestamps

- **Error Handling:**
  - Graceful failure handling for individual processes and documents
  - Summary report of successful and failed exports
  - Detailed logging with timestamps
  - Global error handler for unexpected failures
  - Script waits for user input before closing (prevents console window from disappearing)

## Prerequisites

- PowerShell 5.1 or later
- Network access to your Nintex Process Manager site
- Valid service account credentials with appropriate permissions

## Usage

### Interactive Mode

Simply run the script without parameters to be prompted for all required information:

```powershell
.\Backup-NintexProcessManager.ps1
```

You will be prompted for:
1. Export mode selection (XML, Process Print, or Process Print and Documents)
2. Site URL (e.g., `https://us.promapp.com/siteName`)
3. Username and password
4. Output directory path
5. Whether to include archived processes

### Command-Line Mode

You can also specify the export mode via parameter:

```powershell
.\Backup-NintexProcessManager.ps1 -Mode XMLExport
```

```powershell
.\Backup-NintexProcessManager.ps1 -Mode ProcessPrint
```

```powershell
.\Backup-NintexProcessManager.ps1 -Mode ProcessPrintAndDocuments
```

## Output Structure

The script creates a folder structure that mirrors your Process Manager group hierarchy:

### XMLExport and ProcessPrint Modes

```
OutputDirectory/
├── Group 1/
│   ├── Process A.xml (or .pdf)
│   ├── Process B.xml (or .pdf)
│   └── Subgroup 1/
│       └── Process C.xml (or .pdf)
├── Group 2/
│   └── Process D.xml (or .pdf)
└── _Ungrouped/
    └── Orphaned Process.xml (or .pdf)
```

### ProcessPrintAndDocuments Mode

```
OutputDirectory/
├── Group 1/
│   ├── Process A.pdf
│   ├── Process B.pdf
│   ├── _Documents/
│   │   ├── Document1.docx
│   │   ├── Document2.pdf
│   │   └── Image.jpg
│   └── Subgroup 1/
│       ├── Process C.pdf
│       └── _Documents/
│           └── SubgroupDoc.xlsx
├── Group 2/
│   ├── Process D.pdf
│   └── _Documents/
│       └── Video.mp4
└── _Ungrouped/
    ├── Orphaned Process.pdf
    └── _Documents/
        └── UngroupedDoc.pdf
```

Documents are placed in `_Documents` subfolders within their primary group as defined in Process Manager.

## Authentication

The script uses OAuth2 password grant flow to authenticate with your Process Manager site. The authentication token is valid for the duration specified in the API call (default: 60000 seconds).

### Site URL Format

Your site URL should be in one of these formats:
- `https://us.promapp.com/siteName`
- `https://au.promapp.com/siteName`
- `https://eu.promapp.com/siteName`

The script automatically extracts the tenant ID from the URL path.

## API Endpoints Used

The script interacts with the following Nintex Process Manager APIs:

1. **Authentication**: `POST /oauth2/token`
2. **Process Groups**: `GET /Process/View/GetChildProcessGroupTreeItems`
3. **Process List**: `GET /Bff/Process/api/v1/processes`
4. **XML Export**: `GET /Process/ImportExport/ExportProcess/{processId}`
5. **PDF Export**: `GET /Process/ImportExport/Print`
6. **Document List**: `GET /bff/document/api/v1/documents`
7. **Document Download**: `GET /Documents/View/Open`

## Export Modes Explained

### XML Export

Exports each process as an XML file containing:
- Process metadata (name, version, owner, expert, etc.)
- Process procedures and activities
- Triggers, inputs, and outputs
- Linked stakeholders
- Risk controls and targets
- Full process structure

**Best for**: System migrations, archival, programmatic processing

### Process Print (PDF)

Exports each process as a formatted PDF including:
- Flowchart visualization
- Procedures and tasks
- Business analysis information
- Full notes and descriptions
- Timeframes and costs
- Risk references

**Best for**: Documentation, sharing with stakeholders, compliance

### Process Print and Documents

Exports processes as PDFs and downloads all documents from the site, including:
- All document types (Word, Excel, PowerPoint, PDF, images, videos, etc.)
- Automatic Base64 decoding for text-based documents
- Binary file handling for images and videos
- Documents organized in `_Documents` subfolders within their primary group
- Proper file extension preservation

**Best for**: Complete site backups, disaster recovery, content migration

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| Mode | String | No | Export mode: `XMLExport`, `ProcessPrint`, or `ProcessPrintAndDocuments` |

## Examples

### Example 1: Export All Active Processes as XML

```powershell
.\Backup-NintexProcessManager.ps1 -Mode XMLExport

# When prompted:
# Site URL: https://us.promapp.com/mycompany
# Username: backup.service@company.com
# Password: ********
# Output directory: C:\Backups\ProcessManager\2025-12-08
# Include archived processes? N
```

### Example 2: Export All Processes (Including Archived) as PDF

```powershell
.\Backup-NintexProcessManager.ps1 -Mode ProcessPrint

# When prompted, select 'Y' for including archived processes
```

### Example 3: Complete Site Backup with Processes and Documents

```powershell
.\Backup-NintexProcessManager.ps1 -Mode ProcessPrintAndDocuments

# When prompted:
# Site URL: https://au.promapp.com/mycompany
# Username: backup.service@company.com
# Password: ********
# Output directory: C:\Backups\ProcessManager\Full-Backup-2025-12-08
# Include archived processes? Y
```

This will export:
- All active and archived processes as PDF files
- All documents from the site (Word, Excel, images, videos, etc.)
- Documents organized in `_Documents` subfolders within their primary groups
- Complete folder structure matching the site's group hierarchy

## Progress Tracking

The script provides comprehensive progress tracking to ensure you always know the backup is actively running:

### Real-Time Status Updates

During process and document exports, you'll see a live progress bar showing:
- **Current item count**: e.g., "Processing 45 of 125"
- **Elapsed time**: How long the current phase has been running
- **Processing rate**: Items per second (e.g., "2.5/sec")
- **ETA**: Estimated time remaining to complete the phase
- **Current item**: Name of the process or document being exported

Example progress bar:
```
Exporting Processes
Processing 45 of 125 | Elapsed: 03m 21s | Rate: 0.22/sec | ETA: 06m 04s | Current: Customer Onboarding Process
[███████████████░░░░░░░░░░░░░░░░░] 36%
```

### Phase Completion Summaries

After each major phase completes, you'll see:
- Time taken for that phase
- Success/failure counts
- Overall progress

Example:
```
[2025-12-08 14:23:45] Process export completed in 15m 32s
```

### Console Logging

To prevent console spam during large backups:
- Progress logs appear every 10 items (not for every single export)
- Failures are always logged immediately
- Final summary shows all statistics

### Overall Backup Time

At the end of the backup, the script displays:
- Total backup time across all phases
- Complete statistics for processes and documents
- Final destination path

Example summary:
```
================================================
  Backup Complete
================================================

Total backup time: 47m 18s

Total processes: 125
Successfully exported: 124
Failed process exports: 1

Total documents: 261
Successfully exported: 259
Failed document exports: 2

Backup saved to: C:\Backups\ProcessManager\2025-12-08
```

## Troubleshooting

### Authentication Failures

- Verify your username and password are correct
- Ensure the service account has appropriate permissions
- Check that the site URL is correct and accessible

### Export Failures

Individual process and document export failures are logged but don't stop the script. Check the console output for specific error messages.

Common causes:
- Network connectivity issues during download
- Insufficient permissions to access certain processes or documents
- Corrupted files in the source system
- Disk space limitations on the destination

### Path Length Issues

Windows has a 260-character path limit. The script sanitizes filenames and limits their length, but very deep folder hierarchies combined with long process names may still cause issues. Consider using a shorter output path.

## Performance Considerations

- The script includes a 100ms delay between process exports to avoid overwhelming the server
- Large sites with hundreds of processes may take considerable time to complete
- PDF exports are generally larger and slower than XML exports

## Security Notes

- Credentials are handled securely using PowerShell's `SecureString`
- The authentication token is only stored in memory for the duration of the script
- No credentials are written to disk or logs

## Roadmap

- [x] Document export functionality for ProcessPrintAndDocuments mode
- [ ] Support for parallel process exports
- [ ] Resume capability for interrupted backups
- [ ] Incremental backup support (only export changed processes)
- [ ] Export filtering by group, date, or other criteria
- [ ] Link documents to their associated processes in the export

## License

This script is provided as-is for use with Nintex Process Manager.

## Support

For issues or questions, please contact your Nintex support representative or system administrator.

## Version History

### Version 1.2.6 (2025-12-08)
- **Fixed path construction issues with invalid characters and length limits**
- Now sanitizing group titles when building folder hierarchy
- Prevents invalid characters (especially backslashes) in folder names
- Added Windows MAX_PATH (260 character) validation for process exports
- Added Windows MAX_PATH validation for document exports
- Intelligently truncates filenames when paths exceed limit while preserving file extensions
- Logs warnings when path truncation occurs
- Improved error handling for path-related failures
- Fixes error: "Could not find a part of the path" caused by names like "Innovation \ Renovation"

### Version 1.2.5 (2025-12-08)
- **Added comprehensive URI validation and error diagnostics**
- Added SiteUrl parameter validation to all URI-parsing functions
- Added detailed error messages identifying which function failed
- Added verbose logging for endpoint construction in Get-AllProcesses and Get-AllDocuments
- Added endpoint URL validation before Invoke-RestMethod calls
- Fixed query string escaping with backtick before '?' character
- Enhanced error logging with full error details and endpoint information
- Helps diagnose URI parsing errors with clear diagnostic information

### Version 1.2.4 (2025-12-08)
- **Fixed infinite loop/hang when processing group hierarchy**
- Replaced array slicing with proper ArrayList for queue management
- Added try-catch around API calls to handle individual group failures gracefully
- Enhanced verbose logging to diagnose stuck/hanging groups
- Individual group API failures now log warning and continue instead of hanging
- Better queue size tracking with detailed verbose output

### Version 1.2.3 (2025-12-08)
- **Fixed excessive API calls during group hierarchy retrieval**
- Added queue tracking to prevent queuing the same group multiple times
- Dramatically reduced number of unnecessary API calls
- Groups with `hasChild=true` are now only queued once
- Progress messages now show actual API call count vs unique groups found
- Enhanced verbose logging for queue operations

### Version 1.2.2 (2025-12-08)
- **Fixed group hierarchy duplication bug**
- Added deduplication logic using UniqueId tracking
- Prevents the same group from being counted multiple times
- More accurate group count reporting
- Verbose logging for skipped duplicate groups

### Version 1.2.1 (2025-12-08)
- **Added wait-for-user-input before closing**
- Script now pauses with "Press any key to exit..." message
- Console window stays open after completion or error
- Global error handler catches unexpected failures with detailed error display
- Users can review results before window closes

### Version 1.2.0 (2025-12-08)
- **Enhanced progress tracking and status indicators**
- Real-time elapsed time display for overall backup and individual phases
- Processing rate calculations (items/second)
- Estimated time remaining (ETA) for long-running operations
- Live status updates showing current item being processed
- Reduced console spam with periodic logging (every 10 items)
- Phase completion summaries with time taken
- Group hierarchy discovery progress indicators
- Total backup time in final summary

### Version 1.1.0 (2025-12-08)
- Added document export functionality
- Automatic Base64 decoding for documents
- Documents organized in _Documents subfolders
- Complete ProcessPrintAndDocuments mode implementation
- Enhanced summary reporting with document statistics

### Version 1.0.0 (2025-12-08)
- Initial release
- XML export support
- PDF export support
- Recursive group hierarchy
- Archived process support
- Progress tracking and logging
