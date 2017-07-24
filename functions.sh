function find_replace() {
    sh $BASH_PROFILE_HOME/rename.sh $1 $2 $3
}

function playsound() {
    afplay $BASH_PROFILE_HOME/assets/airhorn.mp3;
}

function hf() {
    history | grep -i $1 | tail -r | less
}

upup(){ DEEP=$1; [ -z "${DEEP}" ] && { DEEP=1; }; for i in $(seq 1 ${DEEP}); do cd ../; done; }

function gcoc() {
    MATCHING=`git branch --list "*$1*"`;
    NUM_MATCHES=`echo $MATCHING | wc -l`;

    if [ $NUM_MATCHES -gt 1 ]
    then
        SAVEIFS=$IFS
        IFS=$'\n'
        #read -A BRANCHES <<< "${MATCHING}"
        BRANCHES=(${=MATCHING})

        select branch in "${BRANCHES[@]}"
        do
            git checkout `echo $branch | xargs`
            break
        done
    else
        git checkout `echo $MATCHING | xargs`
    fi
}

function sendpush() {

    LAST_EXIT_CODE=$?
    CMD=$(fc -ln -1)
    # No point in waiting for the command to complete

    if [ $LAST_EXIT_CODE -eq 0 ]
    then
        VERB="failed";
        ALERT_NAME="$CMD failed with code $LAST_EXIT_CODE";
    else
        VERB="succeeded"
        ALERT_NAME="$CMD succeeded";
    fi

    JSON='{"value1":"'"$CMD"'","value2":"'"$VERB"'","value3":"'"$LAST_EXIT_CODE"'"}';
    curl -s -X POST -H "Content-Type: application/json" -d $JSON https://maker.ifttt.com/trigger/long_running_desktop_task/with/key/kMri90fxHSN2xqBR-xQbC12C-iFWbXnXTbBVfVfvLjD  > /dev/null
}

function ddd {
    echo "Cleaning derived data...";
    setopt localoptions rmstarsilent;
    rm -rf ~/Library/Developer/Xcode/DerivedData/ 2> /dev/null;
    echo "Done."
}

function f_notifyme {
  LAST_EXIT_CODE=$?
  CMD=$(fc -ln -1)
  # No point in waiting for the command to complete
  notifyme "$CMD" "$LAST_EXIT_CODE" &
}

