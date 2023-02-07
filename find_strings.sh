#!/bin/bash

# Find all .swift files in the current directory
find $1 -name "*.swift" | while read file; do
  # Write the filename as a comment in the Localizable.strings file
  echo "/* $file */" >> Localizable.strings

  # Search for strings in quotation marks in each file
  grep -E '".*?"' $file | while read whole_string; do
    # Replace \(.*\) with %@
    string=$(echo $whole_string | grep -oE '".*?"')
    echo $whole_string
    string_with_percent=$(printf %q "$string" | sed -E 's/\\\(.*\)/%@/g' | sed -E 's/\\//g')

    # Extract the comment from the end of the string
    comment=$(echo $string | sed -E 's/.*\\\((.*)\)/\1/g')

    # Write the modified string and comment into the Localizable.strings file
    echo "$string_with_percent = $string_with_percent; /* $whole_string */" >> Localizable.strings
  done
done
