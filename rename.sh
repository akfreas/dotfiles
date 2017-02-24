BACKUP_DIR='_backup';
TARGET_DIR=$1;
SEARCH_STRING=$2;
REPLACE_STRING=$3;

FILE_LIST=`find $TARGET_DIR -type f -not -path "*$BACKUP_DIR*"`
mkdir -pv $BACKUP_DIR;
while IFS= read -r line
do
  echo $line;
  if ! [[ " $list " =~ " $line " ]] ; then
      LC_ALL=C sed -i '' "s%$SEARCH_STRING%$REPLACE_STRING%g" "$line";
  fi
  if [[ $line == *"$SEARCH_STRING"* ]]; then
      newfile=`echo $line | sed "s%$SEARCH_STRING%$REPLACE_STRING%g"`; 
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
