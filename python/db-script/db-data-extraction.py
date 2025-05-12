#!/usr/bin/env python3

# Data Extraction and Text Export Script
# ------------------------------------
# This script extracts user and character data from multiple databases
# and exports the results to a text file with formatted output

import mysql.connector

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

try:
    # Open output file for writing results
    with open('somaz-decentralization.txt', 'w') as file:
        # Connect to primary database
        conn_first = mysql.connector.connect(**db_config_first)
        cursor_first = conn_first.cursor()

        # Initialize counter for numbered output
        counter = 1

        # Process each user address
        for address in user_addresses:
            # Query user information from primary database
            query_first = "SELECT id, game_db_id, nick_name FROM user WHERE address = %s"
            cursor_first.execute(query_first, (address,))
            result_first = cursor_first.fetchone()

            if result_first:
                # Extract and write user information
                user_id, game_db_id, nick_name = result_first
                output_line = f"{counter}. Address: {address}, ID: {user_id}, Game DB ID: {game_db_id}, Nickname: {nick_name}\n"
                file.write(output_line)

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

                # Write character details
                for row in result_second:
                    detail_line = f"   Actor ID: {row[0]}, EXP: {row[1]}, Token ID: {row[2]}\n"
                    file.write(detail_line)

                # Clean up secondary database connection
                cursor_second.close()
                conn_second.close()

                # Increment counter after processing each address
                counter += 1
            else:
                # Handle case where user is not found
                not_found_line = f"{counter}. Address: {address} not found.\n"
                file.write(not_found_line)
                counter += 1

        # Clean up primary database connection
        cursor_first.close()
        conn_first.close()

except mysql.connector.Error as e:
    # Handle database errors
    with open('somaz-decentralization.txt', 'a') as file:
        file.write(f"Database error: {e}\n")

print("\nThe results have been written to 'somaz-decentralization.txt'.")
