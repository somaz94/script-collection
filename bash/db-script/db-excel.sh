#!/bin/bash

# Define variables
DB_HOST=""
DB_USER=""
DB_PASS=""  # Password with special character
DB_NAME=""
TABLE_NAME=""
OUTPUT_PATH="/home/nerdystar/DB"
DATE_STR=$(date +%Y%m%d)

# Path for the Excel file
XLSX_FILE="${OUTPUT_PATH}/${TABLE_NAME}_${DATE_STR}.xlsx"

# Ensure the output directory exists
mkdir -p $OUTPUT_PATH

# Export variables for Python access
export DB_HOST DB_USER DB_PASS DB_NAME TABLE_NAME XLSX_FILE

# Run the Python script to fetch data and create an Excel file
python3 -c "
import os
import pandas as pd
from sqlalchemy import create_engine
import urllib.parse

# Fetch environment variables
db_user = os.getenv('DB_USER')
db_pass = os.getenv('DB_PASS')
db_host = os.getenv('DB_HOST')
db_name = os.getenv('DB_NAME')
table_name = os.getenv('TABLE_NAME')
xlsx_file = os.getenv('XLSX_FILE')

# URL-encode the password
encoded_db_pass = urllib.parse.quote_plus(db_pass)

# MySQL connection string using URL-encoded password
engine = create_engine(f'mysql+pymysql://{db_user}:{encoded_db_pass}@{db_host}/{db_name}')

# SQL query to fetch data
query = f'SELECT address, score, updated_at FROM {table_name} ORDER BY score DESC'

# Fetch data into DataFrame
try:
    df = pd.read_sql(query, engine)
    # Save to Excel
    df.to_excel(xlsx_file, index=False, engine='xlsxwriter')
    print(f'Excel file created at {xlsx_file}')
except Exception as e:
    print(f'Failed to create Excel file: {e}')
"
