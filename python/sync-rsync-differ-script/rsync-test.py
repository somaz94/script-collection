import aiofiles
import asyncio

async def read_file(file_name):
    print(f"Starting to read {file_name}")
    async with aiofiles.open(file_name, 'r') as file:
        content = await file.read()
        print(f"Finished reading {file_name}")
        print(f"Contents of {file_name}: \n{content}\n")

async def main():
    tasks = [read_file('somaz1.txt'), read_file('somaz2.txt')]
    await asyncio.gather(*tasks)
    print("Both files have been read.")

if __name__ == "__main__":
    asyncio.run(main())
