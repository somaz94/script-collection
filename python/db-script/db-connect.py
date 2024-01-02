import mysql.connector
from mysql.connector import Error

try:
    db = mysql.connector.connect(
        host="",
        user="",
        password="",
        database=""
    )
    print("Connected successfully")
except Error as err:
    print("Error: ", err)
    db = None  # Ensure db is defined in case of an error
finally:
    if db and db.is_connected():
        db.close()
