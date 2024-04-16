#!/bin/bash

# Define variables
DB_HOST=""
SECONDARY_DB_HOST=""
DB_USER=""
DB_PASS=""
SECONDARY_DB_PASS=""
DB_NAME=""
SECONDARY_DB_NAME=""
OUTPUT_PATH="/home/nerdystar/DB"
DATE_STR=$(date +%Y%m%d)

# Path for the Excel file
XLSX_FILE="${OUTPUT_PATH}/decent_rarity_specific_excloude_count_${DATE_STR}.xlsx"

# Ensure the output directory exists
mkdir -p $OUTPUT_PATH

# Export variables for Python access
export DB_HOST DB_USER DB_PASS DB_NAME SECONDARY_DB_HOST SECONDARY_DB_PASS SECONDARY_DB_NAME XLSX_FILE

# Run the Python script to fetch data and calculate counts
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
secondary_db_host = os.getenv('SECONDARY_DB_HOST')
secondary_db_pass = os.getenv('SECONDARY_DB_PASS')
secondary_db_name = os.getenv('SECONDARY_DB_NAME')
xlsx_file = os.getenv('XLSX_FILE')

# URL-encode the passwords
encoded_db_pass = urllib.parse.quote_plus(db_pass)
encoded_secondary_db_pass = urllib.parse.quote_plus(secondary_db_pass)

# MySQL connection strings using URL-encoded passwords
primary_engine = create_engine(f'mysql+pymysql://{db_user}:{encoded_db_pass}@{db_host}/{db_name}')
secondary_engine = create_engine(f'mysql+pymysql://{db_user}:{encoded_secondary_db_pass}@{secondary_db_host}/{secondary_db_name}')

# SQL query to fetch data based on status and actor_id, filtering for 'CENTRALIZED' and 'DECENTRALIZED' statuses, excluding specific owner
primary_query = '''
SELECT owner, actor_id, status, token_id
FROM airdrop_character
WHERE status IN ('DECENTRALIZED', 'NOT_REVEAL') AND owner <> '0x000000000000000000000000000000000000dead'
'''

# Fetch data into DataFrame
try:
    df = pd.read_sql(primary_query, primary_engine)
    df['Rarity'] = df['actor_id'].apply(lambda x: 'Common' if str(x).startswith('105') else
                                               'Uncommon' if str(x).startswith('104') else
                                               'Rare' if str(x).startswith('103') else
                                               'Epic' if str(x).startswith('102') else
                                               'Legend' if str(x).startswith('101') else 'Unknown')
    rarity_count = df.groupby('token_id')['Rarity'].value_counts().unstack(fill_value=0)
    rarity_count = rarity_count[['Common', 'Uncommon', 'Rare', 'Epic', 'Legend']]

    # Filter out rows where all rarity values are zero
    rarity_count = rarity_count[(rarity_count.T != 0).any()]

    # Fetch real_owner data from the secondary database
    secondary_query = 'SELECT token_id, real_owner FROM character_real_owner'
    real_owner_df = pd.read_sql(secondary_query, secondary_engine)

    # Merge real_owner data with the rarity count data
    final_df = pd.merge(real_owner_df, rarity_count, on='token_id', how='inner')
    final_df = pd.merge(final_df, df[['token_id', 'owner']], on='token_id', how='left')

    # Reorder columns as required
    final_df = final_df[['real_owner', 'Common', 'Uncommon', 'Rare', 'Epic', 'Legend', 'token_id', 'owner']]

    # Save results to an Excel file
    final_df.to_excel(xlsx_file, index=False, engine='xlsxwriter')
    print(f'Excel file created at {xlsx_file}')
except Exception as e:
    print(f'Failed to create Excel file: {e}')
"
