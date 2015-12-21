alias c='clear'
alias gril='grep -ril'
alias hf='history | grep -i'
alias rp="ps axwww | grep -i"
alias grep="grep --color=always"
alias srp="source bin/activate > /dev/null; source ../bin/activate > /dev/null;"
alias srp="source bin/activate"
alias pb="pbcopy"
alias pbp="pbpaste"
alias cppk="pb < ~/.ssh/id_rsa.pub"
alias cppvk="pb < ~/.ssh/id_rsa"
alias notifyme="osascript -e 'display notification \"Task finished!\" with title \"Hooray!\"'"


#############################
#### Filesystem Actions #####
#############################

#alias cd='pushd > /dev/null'
#alias cdd='popd > /dev/null'
alias up="cd .."
alias desk='cd ~/Desktop'
alias down='cd ~/Downloads'
alias drop='cd ~/Dropbox'
alias drive='cd ~/Google\ Drive'
alias work='cd ~/tm/'
alias mkdirs='mkdir -pv'
alias lns='ln -s'
alias home='cd ~'
alias foldersize="du -sh"
alias cp='cp -r'
alias ll='pwd; ls -Galhs'
alias lll='CLICOLOR_FORCE=1 ls -Galsh | less -R'
alias ramdisk='diskutil erasevolume HFS+ "ramdisk" `hdiutil attach -nomount ram://4194304`'

##################
##### XCode ######
##################

alias cleanderived="rm -rf ~/Library/Developer/Xcode/DerivedData/*"
alias ox="open *.xcodeproj"
alias ow="open *.xcworkspace"

###############
## Git Stuff ##
###############
alias gs='git status'
alias gl='git lg1'
alias gd='git diff --word-diff'
alias gdst='gd --staged'
alias ga='git add -A .'
alias gco='git checkout'
alias gcob='git checkout -b'
alias gf='git fetch origin master'
alias gplom='gpl master'
alias gplod='git pull origin develop'
alias gbr='git branch'
alias gpom='git push origin master'
alias gpos='git push origin socialize'
alias gpod='git push origin develop'
alias gpo='git push origin -u'
alias gpl='git pull --rebase origin'
alias gcam='git commit -am'
alias gcm="git commit -m"
alias gst="git stash"
alias gsa="git stash apply"
alias gsl="git stash list"
alias gss="git stash show"
alias gsho="git show"
alias grhard="git reset --hard"
alias gre="git reset"
alias gcdf="git clean -df"
alias gad="git add -A"
alias gadp="gad --patch"
alias gpa="STASH_COMMIT=`git stash create`;git reset --hard;gpl;git stash apply $STASH_COMMIT;"
alias gbrd="git for-each-ref --sort=-committerdate refs/heads/ --format='%(refname) %(committerdate) %(authorname)' | sed 's/refs\/heads\///g'"

##############
### Bash #####
##############

alias reload="exec $SHELL -l"

##############
#### Make ####
#############

alias m='make'

#############
### Chef ###
############

alias ecdel='yes |knife ec2 server delete --purge'

############
### Ruby ###
############

alias be='bundle exec'

##############
### Python ###
##############



