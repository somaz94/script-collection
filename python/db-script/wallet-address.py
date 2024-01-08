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

# Open a file to write addresses
with open('addresses.txt', 'w') as output_file:
    # Execute MySQL query for each `nid`
    for date, nids in data.items():  # Iterate over each date
        format_strings = ','.join(['%s'] * len(nids))
        cursor.execute("SELECT address FROM user WHERE nid IN (%s)" % format_strings, tuple(nids))

        # Write results to file
        for address in cursor:
            output_file.write(f"{address[0]}\n")

# Close MySQL connection
db.close()
