#!/bin/bash

# Directory to check
DIR="./src"  # Change this to your target directory
SUM_FILE=".temp/checksums.txt"  # File to store checksums
EXCLUDE_FILE=".temp/exclude.txt"

MAIN_ENTRYPOINT=./src/uex1010.cpp

STATS_FILE="./.temp/stats"

COMPILER="g++"

WINDOWS_OBJECT_DEPENDENCIES=""
WINDOWS_COMPILE_DEPNDENCIES=""

LINUX_OBJECT_DEPENDENCIES="  "
LINUX_COMPILE_DEPENDENCIES="  "

SANITIZER="-fsanitize=address"

##
##  STATS FUNCTIONS
##

init_stat() {
    key="$1"
    grep -q "^$key=" "$STATS_FILE" || echo "$key=0" >> "$STATS_FILE"
}

get_stat() {
    grep "^$1=" "$STATS_FILE" | cut -d '=' -f 2
}

increment_stat() {
    key="$1"
    init_stat "$key"
    value=$(get_stat "$key")
    new_value=$((value + 1))
    sed -i "s/^$key=.*/$key=$new_value/" "$STATS_FILE"
}

##
##  MAIN FUNCTIONS
##

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

get_build_number(){
    local full_count=$(get_stat "full_builds")
    local partial_count=$(get_stat "partial_builds")

    # Default to 0 if not found or empty
    full_count=${full_count:-0}
    partial_count=${partial_count:-0}

    echo $((full_count + partial_count))
}

last_compile_step_linux() {

    OBJECTS=$(find .temp/o -type f -name "*.o" | sort)

    #OBJECTS=$(echo "$OBJECTS" | grep -v 'engine.o'; echo ".temp/o/engine.o")
    #OBJECTS=$(echo "$OBJECTS" | grep -v 'main.o'; echo ".temp/o/main.o")

    OBJECTS=$(echo "$OBJECTS" | tr '\n' ' ')

    eval "$COMPILER -DBUILD_NUMBER=$(get_build_number) $OBJECTS -g3 -o .temp/main -Wall -lm $LINUX_COMPILE_DEPENDENCIES"

}


last_compile_step_windows() {

    OBJECTS=$(find .temp/o -type f -name "*.o" | sort)

    OBJECTS=$(echo "$OBJECTS" | grep -v 'engine.o'; echo ".temp/o/engine.o")
    OBJECTS=$(echo "$OBJECTS" | grep -v 'main.o'; echo ".temp/o/main.o")

    OBJECTS=$(echo "$OBJECTS" | tr '\n' ' ')

    eval "$COMPILER -DBUILD_NUMBER=$(get_build_number) .temp/o/* -g3 -o .temp/main.exe -Wall -lm $WINDOWS_COMPILE_DEPNDENCIES" 

}

compile_main_only() {

    eval "$COMPILER -DBUILD_NUMBER=$(get_build_number) $WINDOWS_OBJECT_DEPENDENCIES -c $MAIN_ENTRYPOINT -g3 -Wall -o .temp/o/main.o"     

    if [[ "$COMPILE_FOR_WINDOWS" != false ]]; then
        last_compile_step_windows
    else
        last_compile_step_linux
    fi

}
compile_all() {

    find "$DIR" -type f | while read -r file; do
        if ! is_excluded "$file"; then
            if [[ "$file" == *.cpp ]]; then
                echo $file
                FILENAME=$(basename "$file")
               FILENAME_NO_EXT="${FILENAME%.*}"
                if [[ "$COMPILE_FOR_WINDOWS" ]]; then
                    eval "$COMPILER -DBUILD_NUMBER=$(get_build_number) $WINDOWS_OBJECT_DEPENDENCIES -c $file -g3 -Wall -o .temp/o/$FILENAME_NO_EXT.o"     
                else
                    eval "$COMPILER -DBUILD_NUMBER=$(get_build_number) $LINUX_OBJECT_DEPENDENCIES -c $file -g3 -Wall -o .temp/o/$FILENAME_NO_EXT.o"     
                fi
            fi
            
        #else
            #echo "Skipping excluded file: $file"
        fi
    done

    if [[ "$COMPILE_FOR_WINDOWS" != false ]]; then
        last_compile_step_windows
    else
        last_compile_step_linux
    fi


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
                eval "$COMPILER -DBUILD_NUMBER=$(get_build_number) -Wall -g3 -c -lvulkan $TO_COMPILE_PATH -o .temp/o/$FILENAME_NO_EXT.o"               # Execute the custom command on the changed file
               fi
            fi
            
            if [[ "$file" == *.cpp ]]; then
               echo " + $file"  # Print the changed file path
               FILENAME=$(basename "$file")
               FILENAME_NO_EXT="${FILENAME%.*}"
               eval "$COMPILER -DBUILD_NUMBER=$(get_build_number) -Wall -g3 -c $file -o .temp/o/$FILENAME_NO_EXT.o"               # Execute the custom command on the changed file
            fi
            #$CUSTOM_COMMAND "$file"  # Execute the custom command on the changed file
         done
        #calculate_checksums  # Update the checksum file
    else
        echo "No changes detected."
    fi

    if [[ "$COMPILE_FOR_WINDOWS" != false ]]; then
        last_compile_step_windows
    else
        last_compile_step_linux
    fi 

    calculate_checksums

    #sleep 1
    #.temp/main

    rm "$TEMP_FILE"
}

SKIP_CHECKING=false
ONLY_SHADERS=false
COMPILE_FOR_WINDOWS=false
COMPILE_MAIN_ONLY=false
RUN_AFTER_COMPILE=false
USE_SANITIZER=false

# Main execution
#PARSE ARGUMENTS (--args1)
for var in "$@"
do
    case "$var" in
	-a | --all )
		SKIP_CHECKING=true
		;;
    -s | --shaders )
        ONLY_SHADERS=true
        ;;
    -w | --windows )
        COMPILER="x86_64-w64-mingw32-c++"
        COMPILE_FOR_WINDOWS=true
        ;;
    -m | --main )
        COMPILE_MAIN_ONLY=true
        ;;
    -r | --run )
        RUN_AFTER_COMPILE=true
        ;;
    -san | --sanitizer )
        USE_SANITIZER=true
		  COMPILER="$COMPILER -fsanitize=address"
        ;;
    esac
done


if [ "$ONLY_SHADERS" != false ]; then
    exit 0
fi

echo "Compiler: $COMPILER"

if [ "$COMPILE_MAIN_ONLY" != false ]; then
    echo "Compiling only $MAIN_ENTRYPOINT"
    compile_main_only
elif [ "$SKIP_CHECKING" != false ]; then
    echo "Compiling all files"
    increment_stat "full_builds"
    compile_all
else
    echo "Compiling changed files"
    increment_stat "partial_builds"
    check_changes
fi

if [ "$RUN_AFTER_COMPILE" != false ]; then

    echo "Running program:"
    echo "   === PROGRAM OUTPUT ===   "
    echo
    .temp/main
fi

echo "Done :)"

