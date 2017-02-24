BACKUP_DIR='_backup';
FILE_LIST=`find . -type f -not -path "*$BACKUP_DIR*"`
mkdir -pv $BACKUP_DIR;
while IFS= read -r line
do
    echo $line;
  if ! [[ " $list " =~ " $line " ]] ; then
      LC_ALL=C sed -i '' "s%$1%$2%g" "$line";
  fi
  if [[ $line == *"$1"* ]]; then
      newfile=`echo $line | sed "s%$1%$2%g"`; 
      mkdir -pv "`dirname "$newfile"`"; 
      echo "Copying $line to $newfile";
      cp "$line" "$newfile" 2> /dev/null;
      mv "$line" $BACKUP_DIR 2> /dev/null;
  fi;

  list='\.png \.ttf';


  if [[ " $list " =~ " $line " ]] ; then
      echo "$line matches $list";
  fi


done <<< "$FILE_LIST";
