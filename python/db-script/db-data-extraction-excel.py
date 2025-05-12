#!/usr/bin/env python3

# Data Extraction and Excel Export Script
# -------------------------------------
# This script extracts user and character data from multiple databases
# and exports the results to an Excel file

import mysql.connector
import pandas as pd

# Database Configuration
# --------------------
# Configuration for the primary database (user information)
db_config_first = {
    "host": "",        # Primary database host
    "database": "",    # Primary database name
    "user": "",        # Database username
    "password": ""     # Database password
}

# Base configuration for secondary database (game data)
# Database name will be dynamically set based on game_db_id
db_config_second_base = {
    "host": "",        # Secondary database host
    "user": "",        # Database username
    "password": ""     # Database password
}

# List of user addresses to process
# These are Ethereum wallet addresses to look up
user_addresses = [
    "0xxxxxx22074FExxxxxxxxxxxxxxxxxxxxxxx12A0A",
    "0x140xxxxxx915xxxxxbEAxxxxxxxxxxxxxxx9b1e2",
    "0xaxxxxxxxxxxxxxxxxxxxxxxEEfd7aD1BAB2ea093",
    "0x0154dAxxxxxxxxxxxxxxxxxxxxxxxxxxxx9b2DA2",
    "0x3F6xxxxxxxxxxxxxxxxxxxxxxxxxx920108A39bE"
    # ..more
]

# Initialize data storage
data = []

try:
    # Connect to primary database
    conn_first = mysql.connector.connect(**db_config_first)
    cursor_first = conn_first.cursor()

    # Process each user address
    for address in user_addresses:
        # Query user information from primary database
        query_first = "SELECT id, game_db_id, nick_name FROM user WHERE address = %s"
        cursor_first.execute(query_first, (address,))
        result_first = cursor_first.fetchone()

        if result_first:
            # Extract user information
            user_id, game_db_id, nick_name = result_first

            # Determine game database name based on game_db_id
            db_name = f"game{'00' if game_db_id == 100 else '01'}"

            # Update secondary database configuration
            db_config_second = db_config_second_base.copy()
            db_config_second["database"] = db_name

            # Connect to secondary database
            conn_second = mysql.connector.connect(**db_config_second)
            cursor_second = conn_second.cursor()

            # Query character information
            query_second = "SELECT actor_id, exp, token_id FROM `character` WHERE user_id = %s AND attribution != 1 AND exp != 0 ORDER BY exp DESC;"
            cursor_second.execute(query_second, (user_id,))
            result_second = cursor_second.fetchall()

            # Process character data
            for row in result_second:
                # Combine user and character data
                data.append([address, user_id, game_db_id, nick_name, row[0], row[1], row[2]])

            # Clean up secondary database connection
            cursor_second.close()
            conn_second.close()

        else:
            # Handle case where user is not found
            data.append([address, None, None, None, None, None, None])

    # Clean up primary database connection
    cursor_first.close()
    conn_first.close()

    # Create DataFrame and export to Excel
    df = pd.DataFrame(data, columns=['Address', 'User ID', 'Game DB ID', 'Nickname', 'Actor ID', 'EXP', 'Token ID'])
    df.to_excel('somaz-decentralization.xlsx', index=False)

except mysql.connector.Error as e:
    print(f"Database error: {e}")

print("\nThe results have been written to 'somaz-decentralization.xlsx'.")
