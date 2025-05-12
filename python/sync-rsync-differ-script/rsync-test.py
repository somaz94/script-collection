#!/usr/bin/env python3

# Asynchronous File Reading Test Script
# ---------------------------------
# This script demonstrates asynchronous file reading using aiofiles,
# allowing multiple files to be read concurrently without blocking.

import aiofiles
import asyncio

async def read_file(file_name):
    """Read a file asynchronously and print its contents.
    
    Args:
        file_name (str): Name of the file to read
        
    This function uses aiofiles to perform non-blocking file I/O operations,
    which is particularly useful when reading multiple files concurrently.
    """
    print(f"Starting to read {file_name}")
    async with aiofiles.open(file_name, 'r') as file:
        content = await file.read()
        print(f"Finished reading {file_name}")
        print(f"Contents of {file_name}: \n{content}\n")

async def main():
    """Main function that demonstrates concurrent file reading.
    
    Creates a list of tasks to read multiple files simultaneously
    and waits for all tasks to complete using asyncio.gather.
    """
    # Create tasks for reading multiple files concurrently
    tasks = [read_file('somaz1.txt'), read_file('somaz2.txt')]
    # Wait for all tasks to complete
    await asyncio.gather(*tasks)
    print("Both files have been read.")

if __name__ == "__main__":
    # Run the async main function
    asyncio.run(main())
