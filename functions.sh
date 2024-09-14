function create_ramdisk() {
    size="2048000" # 2.1 GB in blocks
    ramdisk_info_file="/tmp/ramdisk_info.txt"

    # Create and attach the ramdisk
    ramdisk_dev=$(hdiutil attach -nomount ram://2048000 | awk '{ print $1 }' | sed 's/ *$//')
    echo "ramdisk_dev $ramdisk_dev."
    # Partition and format the ramdisk
    #diskutil partitionDisk $ramdisk_dev 1 GPTFormat APFS 'ramdisk' '100%'
    diskutil partitionDisk $ramdisk_dev 1 GPTFormat APFS 'ramdisk' '100%'

    # Write the device identifier to a file
    echo "${ramdisk_dev}" > "${ramdisk_info_file}"

    echo "Ramdisk mounted at ${ramdisk_dev}"
}

#alias ramdisk="diskutil partitionDisk $(hdiutil attach -nomount ram://2048000) 1 GPTFormat APFS 'ramdisk' '100%'"

function destroy_ramdisk() {
    ramdisk_info_file="/tmp/ramdisk_info.txt"

    # Read the device identifier from the file
    ramdisk_dev=$(cat "${ramdisk_info_file}")

    # Unmount and detach the ramdisk
    diskutil unmountDisk "${ramdisk_dev}"
    hdiutil detach "${ramdisk_dev}"

    # Remove the temporary file
    rm -f "${ramdisk_info_file}"

    echo "Ramdisk unmounted and detached"
}

function find_replace() {
    sh $BASH_PROFILE_HOME/rename.sh $1 $2 $3
}

function playsound() {
    afplay /System/Library/Sounds/Submarine.aiff
}

function hf() {
    history | grep -i $1 | tail -r | less
}

function fn() {
    find . -iname "*$1*";
}

function fnin() {

    find . -iname "*$1*" -exec grep -il "$2" '{}' +;
}

function gcmc() {
    #ticket_name="$(git rev-parse --abbrev-ref HEAD | grep --color=never -oh "\([A-Za-z]*-[0-9]\{,5}\)")"
    ticket_name="$(git rev-parse --abbrev-ref HEAD)"
    git commit -m "[$ticket_name] $1"
}

function gcm() {
    export branchname=$(git symbolic-ref --short HEAD)
    git commit -m "$1"
}


function gcmn() {
    export branchname=$(git symbolic-ref --short HEAD)
    git commit --no-verify -m "$1"
}
function openpr() {

    #ticket_name="$(git rev-parse --abbrev-ref HEAD | grep --color=never -oh "\([A-Z]*-[0-9]\{3,4\}\)")"
    ticket_name="$(git rev-parse --abbrev-ref HEAD)"
    temp_file=$(mktemp)
    echo "[$ticket_name] \n\r" > $temp_file
    sed -e "s/JIRA-ID/$ticket_name/g" .github/pull_request_template >> $temp_file
    vi -c 'set wrap' $temp_file
    if [[ $1 ]] then
        hub pull-request -F $temp_file -b $1
    else
        hub pull-request -F $temp_file
    fi
}

function link_xcode_data() {
    if [ -d "$1" ];
    then
        rm -rf ~/Library/Developer/Xcode/UserData
        ln -s $SCRIPTPATH/Xcode/UserData  ~/Library/Developer/Xcode/UserData
    fi
}

function asset_resize() {

    for f in $(find . -name $1)
    do
        if ! [[ "@3x" =~ $f ]] then
            new_filename="${f%.*}@3x.${f##*.}";
            echo "No @3x version to start with, renaming $f to $new_filename";
            mv $f $new_filename;
            f=$new_filename;
        fi
        echo "$f -> ${f//@3x/@2x}, ${f//@3x/}";
        convert "$f" -resize 66.66666% "${f//@3x/@2x}";
        convert "$f" -resize 33.33333% "${f//@3x/}";
    done
}

upup(){ DEEP=$1; [ -z "${DEEP}" ] && { DEEP=1; }; for i in $(seq 1 ${DEEP}); do cd ../; done; }

function gcoc() {
    MATCHING="$(git branch --list "*$1*")
    $(git branch --list --remote "*$1*")";
    NUM_MATCHES=`echo $MATCHING | wc -l`;
    FINAL_MATCH=''

    if [ $NUM_MATCHES -gt 1 ]
    then
        IFS=$'\n'

        BRANCHES=(${=MATCHING})

        select branch in "${BRANCHES[@]}"
        do
            FINAL_MATCH=$branch
            break
        done
    elif [ $NUM_MATCHES -eq 1 ]
    then
        FINAL_MATCH=$MATCHING
    else
        echo "No remote or local branch named $1";
    fi

    FORMATTED_MATCH=`echo $FINAL_MATCH | sed -E "s/[[:space:]]*(origin\/)?//g"`
    git checkout $FORMATTED_MATCH

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
    echo $JSON
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
  #/Users/akfreas/dotfiles/notifyme.py "$CMD" "$LAST_EXIT_CODE" &
}

function swiftlint_modified() {
    git diff --name-only | while read -r file
    do
        # Check if the file has a .swift extension
        if [[ $file == *.swift ]]
        then
            # Run swiftlint on the file
            swiftlint --fix "$file"
        fi
    done
}

