function find_replace() {
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
}

function playsound() {

    afplay $BASH_PROFILE_HOME/assets/airhorn.mp3;

}

function alertme() {
    if [ -n "$1" ];
    then
        ALERT_NAME=" $1";
    else
        ALERT_NAME="";
    fi
    curl -s -X POST -H "Content-Type: application/json" -d '{"value1":"'"$ALERT_NAME"'"}' https://maker.ifttt.com/trigger/long_running_desktop_task/with/key/kMri90fxHSN2xqBR-xQbC12C-iFWbXnXTbBVfVfvLjD  > /dev/null
}
