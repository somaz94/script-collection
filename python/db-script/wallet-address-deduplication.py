#!/usr/bin/env python3

# Wallet Address Deduplication Script
# ---------------------------------
# This script processes a JSON file containing NIDs (Network IDs)
# and retrieves unique wallet addresses from a MySQL database

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

# Initialize set to store unique addresses
# Using a set automatically handles deduplication
unique_addresses = set()

# Process NIDs and Retrieve Addresses
# ---------------------------------
# Iterate through each date and its associated NIDs
for date, nids in data.items():
    # Create dynamic SQL query with correct number of placeholders
    format_strings = ','.join(['%s'] * len(nids))
    cursor.execute("SELECT address FROM user WHERE nid IN (%s)" % format_strings, tuple(nids))

    # Add retrieved addresses to the set
    # Using a set ensures no duplicate addresses are stored
    for address in cursor:
        unique_addresses.add(address[0])

# Output Processing
# --------------
# Write unique addresses to output file
with open('unique_addresses.txt', 'w') as output_file:
    for address in unique_addresses:
        output_file.write(f"{address}\n")

# Cleanup
# -------
# Close database connection
db.close()
