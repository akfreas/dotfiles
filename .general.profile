alias c='clear'
function gril() {
    grep -ril --exclude-dir=node_modules $1 . 
}

function gri() {
    grep -ri --exclude-dir=node_modules $1 .
}
alias rp="ps axwww | grep -i"
alias grep="grep --color=always"
alias srp="source bin/activate > /dev/null; source ../bin/activate > /dev/null;"
alias srp="source bin/activate"
alias pb="pbcopy"
alias pbp="pbpaste"
alias cppk="pb < ~/.ssh/id_rsa.pub"
alias cppvk="pb < ~/.ssh/id_rsa"
alias notifyme="osascript ~/dotfiles/notifyme.osascript"
alias ksdiff='/Applications/p4merge.app/Contents/Resources/launchp4merge'

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

unamestr=`uname`
if [[ "$unamestr" == 'Linux' ]]; then
    alias ll='pwd; ls --color -Galsh'
elif [[ "$unamestr" == 'Darwin' ]]; then
    alias ll='pwd; ls -Galhs'
fi
alias lll='CLICOLOR_FORCE=1 ls -Galsh | less -R'
alias ramdisk="diskutil partitionDisk $(hdiutil attach -nomount ram://2048000) 1 GPTFormat APFS 'ramdisk' '100%'"

##################
##### XCode ######
##################

alias ox="open *.xcodeproj"
alias ow="open *.xcworkspace"
alias deriveddata="cd ~/Library/Developer/Xcode/DerivedData/"
alias pprofiles="cd ~/Library/MobileDevice/Provisioning\ Profiles"


###############
## Git Stuff ##
###############
alias gs='git status'
alias gl='git lg1'
alias gr='git rf'
alias gd='git diff --word-diff'
alias gdst='gd --staged'
alias gaa='git add -A .'
alias gco='git checkout'
alias gcob='git checkout -b'
alias gf='git fetch --all'
alias gplom='gpl master'
alias gplod='git pull origin develop'
alias gbr='git branch'
alias gpom='git push origin master'
alias gpos='git push origin socialize'
alias gpod='git push origin develop'
alias gpo='git push origin -u'
alias gpl='git pull origin'
alias gcam='git commit -am'
alias gst="git stash push"
alias gsa="git stash apply"
alias gsl="git stash list"
alias gss="git stash show"
alias gsho="git show"
alias grhard="git reset --hard"
alias gre="git reset"
alias gcdf="git clean -df"
alias gadu="git add -u"
alias gad="git add --all"
alias gadp="gad --patch"
alias gbrd="git for-each-ref --sort=-committerdate refs/heads/ --format='%(refname) %(committerdate) %(authorname)' | sed 's/refs\/heads\///g'"
alias gadt="git add -u"

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


##############
### Docker ###
##############

alias dockershell='bash --login "/Applications/Docker/Docker Quickstart Terminal.app/Contents/Resources/Scripts/start.sh"'
alias dc='docker-compose'
alias dm='docker-machine'

##############
#### AWS #####
##############

alias kmsDecryptClipboard='aws kms decrypt --ciphertext-blob fileb://<(pbpaste | base64 --decode) --output text --query Plaintext | base64 --decode'
alias sls='node ./node_modules/serverless/bin/serverless.js'


