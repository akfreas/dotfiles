'
# File Replacement and Backup Script

This script is designed to search through files within a specified directory, replace occurrences of a search string with a replacement string, and backup the original files.
It will rename every instance of that string, found not only in the files themselves, but also in the filename and directory name.

## Features

- Searches for files containing a specific string.
- Replaces the found string with a new string.
- Moves files and directories matching the string to a new filename
- Backups original files before making changes.
- Ignores binary files such as `.png` and `.ttf`. Add more as you see fit.
- Excludes `.git` directory, the backup directory itself, and `node_modules` from the search.

## Usage

To use this script, you will need to provide three arguments:
1. `TARGET_DIR`: The directory where the script will search for files.
2. `SEARCH_STRING`: The string to search for within the files.
3. `REPLACE_STRING`: The string to replace the search string with.

### Example

```sh
sh script.sh /path/to/target/dir "search_string" "replace_string"
```

## Requirements

- The script is intended to be run in a UNIX-like environment with Bash.
- `sed` needs to be available on the system for string replacement.
- `grep` is used for searching strings within files.

## How It Works

1. The script defines a backup directory where original files will be stored before modification.
2. It generates a list of all files in the `TARGET_DIR` while excluding `.git`, backup directory, and `node_modules`.
3. For each file, if the file does not match the ignore list and contains the `SEARCH_STRING`, the script:
   - Replaces `SEARCH_STRING` with `REPLACE_STRING`.
   - If the filename contains `SEARCH_STRING`, it copies the modified file to a new location reflecting the name change and moves the original file to the backup directory.

## Important Notes

- The script uses `LC_ALL=C` with `sed` to handle binary files safely and ensure consistent behavior across different locales.
- It creates the necessary directories for the new file locations if they do not exist.
- Files with names that contain the search string are handled separately: they are copied to a new location with the replacement string in their name, and the original file is moved to the backup directory.

## Limitations

- The script does not recursively handle directories in the ignore list. Only direct matches are ignored.
- It is designed to ignore only specific binary file types. Additional types should be added to the `IGNORE_LIST` variable as needed.
'


BACKUP_DIR='_backup';
TARGET_DIR=$1;
SEARCH_STRING=$2;
REPLACE_STRING=$3;

IGNORE_LIST='\.png \.ttf';

FILE_LIST=`find $TARGET_DIR -type f -not -path "*.git*" -not -path "*$BACKUP_DIR*" -not -path "*/node_modules/*"`
mkdir -pv $BACKUP_DIR;
while IFS= read -r line
do
  if ! [[ " $IGNORE_LIST " =~ " $line " ]] && grep -q $SEARCH_STRING "$line"; then
      echo "Replace $SEARCH_STRING with $REPLACE_STRING in $line";
      LC_ALL=C sed -i '' "s%$SEARCH_STRING%$REPLACE_STRING%g" "$line";
  fi
  if [[ $line == *"$SEARCH_STRING"* ]]; then
      newfile=`echo $line | sed "s%$SEARCH_STRING%$REPLACE_STRING%g"`; 
      mkdir -pv "`dirname "$newfile"`"; 
      echo "Copying $line to $newfile";
      cp "$line" "$newfile" 2> /dev/null;
      mv "$line" $BACKUP_DIR 2> /dev/null;
  fi;

done <<< "$FILE_LIST";
