#!/usr/bin/env python3

# Database Connection Script
# ------------------------
# This script demonstrates a basic MySQL database connection
# It includes error handling and proper connection cleanup

import mysql.connector
from mysql.connector import Error

try:
    # Attempt to establish database connection
    # Replace empty strings with actual connection details
    db = mysql.connector.connect(
        host="",        # Database host address
        user="",        # Database username
        password="",    # Database password
        database=""     # Database name
    )
    print("Connected successfully")
except Error as err:
    # Handle any connection errors
    print("Error: ", err)
    db = None  # Ensure db is defined in case of an error
finally:
    # Clean up: close the connection if it exists and is connected
    if db and db.is_connected():
        db.close()
