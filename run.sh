#!/bin/bash

# Directory to check
DIR="./"  # Change this to your target directory
SUM_FILE=".temp/checksums.txt"  # File to store checksums
CUSTOM_COMMAND="echo File changed:"  # Change this to your desired command
EXCLUDE_PATH=./tools
EXCLUDE_FILE="exclude.txt"

is_excluded() {
    local file="$1"
    while IFS= read -r exclude; do
        if [[ "$file" == "$exclude" || "$file" == "$exclude"* ]]; then
            return 0  # Excluded
        fi
    done < "$EXCLUDE_FILE"
    return 1  # Not excluded
}

# Function to calculate and store checksums
calculate_checksums() {
    # Create a temporary file for checksums
    TEMP_SUMS=$(mktemp)

    # Calculate checksums excluding specified files and directories
    find "$DIR" -type f | while read -r file; do
        if ! is_excluded "$file"; then
            md5sum "$file" >> "$TEMP_SUMS"
        #else
            #echo "Skipping excluded file: $file"
        fi
    done

    mv "$TEMP_SUMS" "$SUM_FILE"  # Update the checksum file
}

# Function to check for changes
check_changes() {
    if [ ! -f "$SUM_FILE" ]; then
        echo "Checksum file does not exist. Calculating checksums..."
        calculate_checksums
        return
    fi

    if ! [ -d "./.temp/o/" ]; then
        mkdir ./.temp/o
    fi
    #$(pkg-config gtkmm-2.4 --cflags)
    clear
    
    TEMP_FILE=$(mktemp)
    find "$DIR" -type f | while read -r file; do
        if ! is_excluded "$file"; then
            md5sum "$file" >> "$TEMP_FILE"
        #else
            #echo "Skipping excluded file: $file"
        fi
    done
    # Compare the current checksums with the stored checksums
    CHANGES=$(diff "$SUM_FILE" "$TEMP_FILE")

    if [ -n "$CHANGES" ]; then
        echo "Changes detected!"
        
        # Extract changed file paths
         echo "$CHANGES" | grep '^>' | awk '{print $3}' | while read -r file; do

            EXCLUDED=0

            for exclude in "${EXCLUDED_PATHS[@]}"; do
                if [[ "$file" == "$exclude" || "$file" == "$exclude"* ]]; then
                    #echo "Skipping compiling excluded file: $file"
                    EXCLUDED=1
                    break
                fi
            done

            if [[ $EXCLUDED -eq 1 ]]; then
                continue  # Skip this file
            fi

            #Compile changes for .h files
            if [[ "$file" == *.h ]]; then
               # Print the changed file path
               FILENAME=$(basename "$file")
               FILENAME_NO_EXT="${FILENAME%.*}"

               TO_COMPILE_PATH="${file%.*}.cpp"

               if [ -d "$TO_COMPILE_PATH" ]; then
                echo " * $TO_COMPILE_PATH"
                eval "g++ -c $TO_COMPILE_PATH -o .temp/o/$FILENAME_NO_EXT".o               # Execute the custom command on the changed file
               fi
            fi
            
            if [[ "$file" == *.cpp ]]; then
               echo " + $file"  # Print the changed file path
               FILENAME=$(basename "$file")
               FILENAME_NO_EXT="${FILENAME%.*}"
               eval "g++ -c $file -o .temp/o/$FILENAME_NO_EXT".o               # Execute the custom command on the changed file
            fi
            #$CUSTOM_COMMAND "$file"  # Execute the custom command on the changed file
         done
        #calculate_checksums  # Update the checksum file
    else
        echo "No changes detected."
    fi

    g++ .temp/o/* -o .temp/main -Wall -lm -lglfw -lvulkan -lX11 -lxcb -lX11-xcb
    calculate_checksums

    sleep 1
    .temp/main

    rm "$TEMP_FILE"
}

# Main execution
case "$1" in
    calculate)
        calculate_checksums
        ;;
    check)
        check_changes
        ;;
    *)
        echo "Usage: $0 {calculate|check}"
        exit 1
        ;;
esac