function clean_localhost ()
    for f in `find . -type f -name "*Info.plist" -exec grep -l "localhost:8080" {} ";"`; do
        sed -i "" "s/localhost:8080/ha-testing.agilexhealth.com:8080/g" $f;
        echo "Cleaned up $f";
    done;
end

function find_replace()
    FILES_MOVED=[0]=""
    for f in `find . -type f  -exec grep -l $1 {} ";"`; do
        sed -i "" "s/$1/$2/g" $f;
        echo "Replaced $1 with $2 in $f."
    done;


    let x=0;
    for f in `find . -name "*$1*"`; do
       #echo " $f ${f/$1*./$2.}"
       NEW=`dirname $f`"/"${f/$1*./$2.}
       let "x+=1";
       mv $f $NEW
       echo "Moved $f to $NEW."
   done; 
   echo $x
   echo $FILES_MOVED
end

function jirabranch()
    for b in `git branch -r`;
         do echo -n "$b   ";
         i=`echo $b | awk '/origin\/feature\/.*/{gsub(/origin\/feature\//, ""); print}'`
         if [ "$i" != "" ]; then
             curl -s --globoff "https://issues.ridecharge.com/browse/${i}?os_username=alex&os_password=Taxi2012" | awk '/<title>/{gsub(/<\/?title>/,"");print}'
         else
             echo -e
          fi;
           
    done;
end

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

