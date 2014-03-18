#!/bin/bash
ROOT_DIR="$HOME/root"  # your target dir
FILTER_FILE="$HOME/filter.sed"  # the sed script for renaming

# custom rename function that uses $FILTER_FILE (via sed)
function rename_using_filter {
    CURRENT_NAME="$1"
    NEW_NAME="$(echo $1 | sed -f $FILTER_FILE)"  # derive new name
    if [ "$CURRENT_NAME" != "$NEW_NAME" ]; then  # rename if diff
        mv "$CURRENT_NAME" "$NEW_NAME"
    fi
}

# for each directory, starting from deepest first
while IFS= read -r -d $'\0' DIR_NAME; do
    cd "$DIR_NAME"           # go to target dir

    # for each file/dir at this level
    while IFS= read -r -d $'\0' FILE_NAME; do
        if [ -f "$FILE_NAME" ]; then                # if it's a file
            sed -i -f "$FILTER_FILE" "$FILE_NAME"   # replace content
        fi
        rename_using_filter "$FILE_NAME"  # rename it 
    done < <(find . -maxdepth 1 -print0)

    cd - > /dev/null         # back to original dir. Suppress stdout
done < <(find $ROOT_DIR -depth -type d -print0) # get only dirs
