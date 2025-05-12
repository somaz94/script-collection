#!/usr/bin/env python3

# Score Retrieval Script
# --------------------
# This script retrieves contribution scores for a list of addresses
# from a MySQL database and writes them to a text file

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
# Read list of addresses from JSON file
with open('address.json') as file:
    addresses = json.load(file)  # Load list of addresses to process

# Score Retrieval and Output
# -----------------------
# Open output file for writing scores
with open('scores.txt', 'w') as output_file:
    # Prepare SQL query with dynamic parameter placeholders
    # Creates a query like: SELECT address, score FROM contribution_rank WHERE address IN (%s, %s, ...)
    query = "SELECT address, score FROM contribution_rank WHERE address IN ({})"
    format_strings = ','.join(['%s'] * len(addresses))
    query = query.format(format_strings)

    # Execute query with all addresses as parameters
    cursor.execute(query, tuple(addresses))

    # Write results to file in CSV format
    for address, score in cursor:
        output_file.write(f"{address}, {score}\n")

# Cleanup
# -------
# Close database connection
db.close()
