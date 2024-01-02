import json
import mysql.connector

# MySQL connection setup
db = mysql.connector.connect(
    host="",
    user="",
    password="",
    database=""
)

cursor = db.cursor()

# Read JSON file
with open('address.json') as file:
    addresses = json.load(file)  # Assuming this loads a list of addresses

# Open a file to write scores
with open('scores.txt', 'w') as output_file:
    # Prepare query and parameters
    query = "SELECT address, score FROM contribution_rank WHERE address IN ({})"
    format_strings = ','.join(['%s'] * len(addresses))
    query = query.format(format_strings)

    # Execute MySQL query for each address
    cursor.execute(query, tuple(addresses))

    # Write results to file
    for address, score in cursor:
        output_file.write(f"{address}, {score}\n")

# Close MySQL connection
db.close()
