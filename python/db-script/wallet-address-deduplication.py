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
with open('nids.json') as file:
    data = json.load(file)

# Use a set to store unique addresses
unique_addresses = set()

# Execute MySQL query for each `nid`
for date, nids in data.items():  # Iterate over each date
    format_strings = ','.join(['%s'] * len(nids))
    cursor.execute("SELECT address FROM user WHERE nid IN (%s)" % format_strings, tuple(nids))

    # Add results to the set
    for address in cursor:
        unique_addresses.add(address[0])

# Open a file to write unique addresses
with open('unique_addresses.txt', 'w') as output_file:
    for address in unique_addresses:
        output_file.write(f"{address}\n")

# Close MySQL connection
db.close()
