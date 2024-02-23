import mysql.connector

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

try:
    # Open a file to write the results
    with open('somaz-decentralization.txt', 'w') as file:
        # Connect to the first database
        conn_first = mysql.connector.connect(**db_config_first)
        cursor_first = conn_first.cursor()

        # Initialize a counter for numbering
        counter = 1

        for address in user_addresses:
            query_first = "SELECT id, game_db_id, nick_name FROM user WHERE address = %s"
            cursor_first.execute(query_first, (address,))
            result_first = cursor_first.fetchone()

            if result_first:
                user_id, game_db_id, nick_name = result_first
                output_line = f"{counter}. Address: {address}, ID: {user_id}, Game DB ID: {game_db_id}, Nickname: {nick_name}\n"
                file.write(output_line)

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
                    detail_line = f"   Actor ID: {row[0]}, EXP: {row[1]}, Token ID: {row[2]}\n"
                    file.write(detail_line)

                cursor_second.close()
                conn_second.close()

                # Increment the counter after processing each address
                counter += 1
            else:
                not_found_line = f"{counter}. Address: {address} not found.\n"
                file.write(not_found_line)
                # Increment the counter even if the address is not found
                counter += 1

        cursor_first.close()
        conn_first.close()
except mysql.connector.Error as e:
    with open('somaz-decentralization.txt', 'a') as file:
        file.write(f"Database error: {e}\n")

# Inform the user that the output has been written to the file
print("\nThe results have been written to 'somaz-decentralization.txt'.")
