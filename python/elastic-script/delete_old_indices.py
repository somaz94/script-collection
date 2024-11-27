#!/usr/bin/env python3

import argparse
import sys
import requests
import datetime
import platform
import re
from typing import Optional

###################
# Global Variables #
###################

# Elasticsearch connection settings
ELASTIC_USER = "elastic"
ELASTIC_PASSWORD = ""  # password
ELASTIC_HOST = ""  # url

# Index pattern to match
INDEX_PATTERN = "logstash-"

# Retention period settings
MIN_RETENTION_DAYS = 7
DEFAULT_RETENTION_DAYS = 30

def parse_arguments() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description='Delete Elasticsearch indices older than specified retention period.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f'''
Examples:
    %(prog)s         # Delete indices older than {DEFAULT_RETENTION_DAYS} days
    %(prog)s -d 60   # Delete indices older than 60 days
    %(prog)s --days 60   # Same as above

Note: Minimum retention period is {MIN_RETENTION_DAYS} days for safety.
        '''
    )
    
    parser.add_argument(
        '-d', '--days',
        type=int,
        default=DEFAULT_RETENTION_DAYS,
        help=f'Number of days to retain indices (default: {DEFAULT_RETENTION_DAYS}, minimum: {MIN_RETENTION_DAYS})'
    )
    
    return parser.parse_args()

def get_threshold_date(retention_days: int) -> str:
    """Calculate threshold date based on retention period."""
    today = datetime.datetime.now()
    threshold = today - datetime.timedelta(days=retention_days)
    return threshold.strftime('%Y.%m.%d')

def get_indices() -> Optional[list]:
    """Retrieve all logstash indices from Elasticsearch."""
    try:
        response = requests.get(
            f"{ELASTIC_HOST}/_cat/indices?v",
            auth=(ELASTIC_USER, ELASTIC_PASSWORD),
            verify=False
        )
        response.raise_for_status()
        
        # Extract index names starting with INDEX_PATTERN
        indices = []
        for line in response.text.splitlines()[1:]:  # Skip header line
            index_name = line.split()[2]
            if index_name.startswith(INDEX_PATTERN):
                indices.append(index_name)
        
        return indices
    except requests.exceptions.RequestException as e:
        print(f"Error: Failed to retrieve indices: {e}", file=sys.stderr)
        return None

def delete_index(index_name: str) -> bool:
    """Delete specified index from Elasticsearch."""
    try:
        response = requests.delete(
            f"{ELASTIC_HOST}/{index_name}",
            auth=(ELASTIC_USER, ELASTIC_PASSWORD),
            verify=False
        )
        response.raise_for_status()
        return True
    except requests.exceptions.RequestException as e:
        print(f"Error deleting index {index_name}: {e}", file=sys.stderr)
        return False

def main():
    # Parse command line arguments
    args = parse_arguments()
    
    # Validate retention days
    if args.days < MIN_RETENTION_DAYS:
        print(f"Error: Retention period cannot be less than {MIN_RETENTION_DAYS} days", file=sys.stderr)
        sys.exit(1)
    
    # Calculate threshold date
    threshold_date = get_threshold_date(args.days)
    
    # Get all indices
    indices = get_indices()
    if not indices:
        print("Error: Failed to retrieve indices or no indices found")
        sys.exit(1)
    
    # Process indices
    for index in indices:
        # Extract date from index name
        match = re.search(f'{INDEX_PATTERN}(.+)', index)
        if not match:
            print(f"Warning: Skipping {index} - Invalid format")
            continue
        
        index_date = match.group(1)
        
        # Validate date format
        if not re.match(r'^\d{4}\.\d{2}\.\d{2}$', index_date):
            print(f"Warning: Skipping {index} - Invalid date format")
            continue
        
        # Check if index is older than threshold
        if index_date < threshold_date:
            print(f"Deleting index: {index} (older than {threshold_date})")
            if delete_index(index):
                print(f"Successfully deleted index: {index}")
        else:
            print(f"Skipping index: {index} (newer than or equal to {threshold_date})")

if __name__ == "__main__":
    # Disable SSL warnings
    requests.packages.urllib3.disable_warnings()
    main()
