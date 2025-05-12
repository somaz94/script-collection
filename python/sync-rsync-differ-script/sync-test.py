#!/usr/bin/env python3

# Synchronous File Reading Test Script
# --------------------------------
# This script demonstrates synchronous file reading,
# reading files sequentially one after another.

def read_file(file_name):
    """Read a file synchronously and print its contents.
    
    Args:
        file_name (str): Name of the file to read
        
    Returns:
        str: Contents of the file
        
    This function performs blocking I/O operations,
    reading one file at a time.
    """
    with open(file_name, 'r') as file:
        print(f"Reading {file_name}...")
        data = file.read()
        print(f"Finished reading {file_name}.")
        print(f"Contents of {file_name}: \n{data}\n")
        return data

def main():
    """Main function that demonstrates sequential file reading.
    
    Reads multiple files one after another,
    waiting for each file to complete before starting the next.
    """
    # Read files sequentially
    data1 = read_file('somaz1.txt')
    data2 = read_file('somaz2.txt')
    print("Both files have been read.")

if __name__ == "__main__":
    main()
