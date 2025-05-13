# Harbor Image Cleanup Script

A robust tool for cleaning up old images from Harbor repositories while keeping the most recent ones.

## Overview

This script helps manage Docker images in Harbor repositories by automatically deleting older images while preserving a specified number of the most recent ones. It supports batch processing, multiple repositories, and provides dry-run capabilities for testing before actual deletion.

## Features

- Clean up multiple repositories in a single run
- Process all repositories in a project with one command
- Keep a configurable number of the newest images
- Parallel deletion with configurable batch size
- Dry-run mode to preview deletions without making changes
- Auto-confirmation option for automated cleanup jobs
- Detailed logging and error handling

## Requirements

- Bash shell
- `curl` for API requests
- `jq` for JSON parsing

## Usage

```bash
./harbor-image-cleanup.sh [options]
```

### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message and exit |
| `-d, --debug` | Enable debug mode for verbose output |
| `--dry-run` | Don't actually delete images, just print what would be deleted |
| `--auto-confirm` | Skip confirmation and automatically delete images |
| `-k, --keep N` | Keep the newest N images (default: 100) |
| `-p, --project NAME` | Harbor project name (default: projectm) |
| `-r, --repo NAME` | Repository name (e.g., game/cache). Can be specified multiple times |
| `-r all` | Process all repositories in the project |
| `-b, --batch-size N` | Number of images to delete in parallel (default: 10) |

### Examples

1. Dry run for a single repository, keeping 50 newest images:
   ```bash
   ./harbor-image-cleanup.sh --dry-run -k 50 -p projectm -r game/cache -b 20
   ```

2. Clean up multiple repositories with auto-confirmation:
   ```bash
   ./harbor-image-cleanup.sh -p projectm -r game/cache -r game -k 20 --auto-confirm
   ```

3. Clean up all repositories in a project:
   ```bash
   ./harbor-image-cleanup.sh -p projectm -r all -k 50
   ```

## Configuration

The script uses the following default configuration, which can be overridden with command-line options:

```
Harbor URL: harbor.concrit.us
Protocol: http
User: admin
Project: projectm
Default repository: game/cache
Images to keep: 100
Batch size: 10
```

## How It Works

1. The script authenticates with the Harbor API
2. It retrieves the list of repositories (or uses the ones specified)
3. For each repository, it:
   - Gets the artifact count
   - Determines which images to keep/delete based on creation date
   - Confirms with the user (unless auto-confirm is enabled)
   - Deletes images in batches for better performance

## Error Handling

The script includes robust error handling:
- Validates required commands before execution
- Tries multiple API endpoints to handle different Harbor versions
- Handles connection issues and invalid responses
- Provides detailed error messages and diagnostics

## Scheduling with Cron

For automated cleanup, you can schedule the script with cron:

```bash
# Example: Run cleanup every day at 2 AM with auto-confirmation
0 2 * * * /path/to/harbor-image-cleanup.sh -p projectm -r all -k 50 --auto-confirm > /var/log/harbor-cleanup.log 2>&1
```

## Troubleshooting

If you encounter issues:

1. Run with `--debug` flag for verbose output
2. Check Harbor API version compatibility
3. Verify network connectivity to Harbor server
4. Ensure proper authentication credentials
