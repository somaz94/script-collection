def read_file(file_name):
    with open(file_name, 'r') as file:
        print(f"Reading {file_name}...")
        data = file.read()
        print(f"Finished reading {file_name}.")
        print(f"Contents of {file_name}: \n{data}\n")
        return data

def main():
    data1 = read_file('somaz1.txt')
    data2 = read_file('somaz2.txt')
    print("Both files have been read.")

if __name__ == "__main__":
    main()
