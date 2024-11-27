# Elasticsearch Index Cleanup Script

This Python script automatically cleans up old Logstash indices in Elasticsearch.

## Installation

1. Create and activate a virtual environment:

```bash
# Create virtual environment
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate

```

2. Install required packages:

```bash
pip install requests
```

## Usage

1. Make sure the virtual environment is activated before running the script:

```bash
source venv/bin/activate
```

2. Run the script:

```bash
# Run with default retention period (30 days)
python delete_old_indices.py

# Run with specific retention period (e.g., 60 days)
python delete_old_indices.py -d 60
# or
python delete_old_indices.py --days 60
```

## Options

- `-h`, `--help`: Display help message
- `-d DAYS`, `--days DAYS`: Set index retention period (default: 30 days, minimum: 7 days)

## Important Notes

- Minimum retention period is set to 7 days for safety
- Before running the script, verify the following settings in `delete_old_indices.py`:
  - `ELASTIC_USER`: Elasticsearch username
  - `ELASTIC_PASSWORD`: Elasticsearch password
  - `ELASTIC_HOST`: Elasticsearch host URL

## Deactivating Virtual Environment

When finished, deactivate the virtual environment:

```bash
deactivate
```

## Requirements

- Python 3.x
- `requests` library
