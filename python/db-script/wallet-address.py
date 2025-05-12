#!/usr/bin/env python3

# Wallet Address Retrieval Script
# ----------------------------
# This script processes a JSON file containing NIDs (Network IDs)
# and retrieves corresponding wallet addresses from a MySQL database

import json
import mysql.connector

# Database Connection Setup
# ----------------------
# Establish connection to MySQL database
# Replace empty strings with actual connection details
db = mysql.connector.connect(
    host="",        # Database host address
    user="",        # Database username
    password="",    # Database password
    database=""     # Database name
)

cursor = db.cursor()

# Input Processing
# --------------
# Read NID data from JSON file
# Expected format: {"date": ["nid1", "nid2", ...], ...}
with open('nids.json') as file:
    data = json.load(file)

# Address Retrieval and Output
# -------------------------
# Open output file for writing addresses
with open('addresses.txt', 'w') as output_file:
    # Process each date and its associated NIDs
    for date, nids in data.items():
        # Create dynamic SQL query with correct number of placeholders
        format_strings = ','.join(['%s'] * len(nids))
        cursor.execute("SELECT address FROM user WHERE nid IN (%s)" % format_strings, tuple(nids))

        # Write retrieved addresses to file
        # Note: This version keeps all addresses, including duplicates
        for address in cursor:
            output_file.write(f"{address[0]}\n")

# Cleanup
# -------
# Close database connection
db.close()
