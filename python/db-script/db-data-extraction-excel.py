import mysql.connector
import pandas as pd

# Database configuration for the first MySQL connection
db_config_first = {
    "host": "",
    "database": "",
    "user": "",
    "password": ""
}

# Database configuration for the second MySQL connection (without specifying the database yet)
db_config_second_base = {
    "host": "",
    "user": "",
    "password": ""
}

user_addresses = [
    "0xxxxxx22074FExxxxxxxxxxxxxxxxxxxxxxx12A0A",
    "0x140xxxxxx915xxxxxbEAxxxxxxxxxxxxxxx9b1e2",
    "0xaxxxxxxxxxxxxxxxxxxxxxxEEfd7aD1BAB2ea093",
    "0x0154dAxxxxxxxxxxxxxxxxxxxxxxxxxxxx9b2DA2",
    "0x3F6xxxxxxxxxxxxxxxxxxxxxxxxxx920108A39bE"
    # ..more
]

# Initialize an empty list to store the data
data = []

try:
    # Connect to the first database
    conn_first = mysql.connector.connect(**db_config_first)
    cursor_first = conn_first.cursor()

    for address in user_addresses:
        query_first = "SELECT id, game_db_id, nick_name FROM user WHERE address = %s"
        cursor_first.execute(query_first, (address,))
        result_first = cursor_first.fetchone()

        if result_first:
            user_id, game_db_id, nick_name = result_first

            # Construct the database name based on game_db_id
            db_name = f"game{'00' if game_db_id == 100 else '01'}"

            # Update the database name in the second db configuration
            db_config_second = db_config_second_base.copy()
            db_config_second["database"] = db_name

            # Connect to the second database
            conn_second = mysql.connector.connect(**db_config_second)
            cursor_second = conn_second.cursor()

            # Execute the query on the second database with updated condition
            query_second = "SELECT actor_id, exp, token_id FROM `character` WHERE user_id = %s AND attribution != 1 AND exp != 0 ORDER BY exp DESC;"
            cursor_second.execute(query_second, (user_id,))
            result_second = cursor_second.fetchall()

            for row in result_second:
                # Append each row to the data list
                data.append([address, user_id, game_db_id, nick_name, row[0], row[1], row[2]])

            cursor_second.close()
            conn_second.close()

        else:
            # Append a not found row to the data list
            data.append([address, None, None, None, None, None, None])

    cursor_first.close()
    conn_first.close()

    # Convert the list to a DataFrame
    df = pd.DataFrame(data, columns=['Address', 'User ID', 'Game DB ID', 'Nickname', 'Actor ID', 'EXP', 'Token ID'])

    # Write the DataFrame to an Excel file
    df.to_excel('somaz-decentralization.xlsx', index=False)

except mysql.connector.Error as e:
    print(f"Database error: {e}")

print("\nThe results have been written to 'somaz-decentralization.xlsx'.")
