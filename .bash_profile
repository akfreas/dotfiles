export  BASH_PROFILE_HOME=$HOME/dotfiles
# NOTE: There is probably a sexier nicer way to do this, but until I figure that out I am manually unsetting here.
# Unsets PATH
set -g -x PATH

# This allows us to use Homebrew versions of things (like git) rather than the pre-installed or XCode installed versions.
# See http://blog.grayghostvisuals.com/git/how-to-keep-git-updated/ for reference.
set -g -x PATH $PATH /usr/local/bin $HOME/.rbenv/bin
# Sets necessary PATH defaults
set -g -x PATH $PATH /usr/bin /bin /usr/sbin /sbin

export  SCRATCH=$BASH_PROFILE_HOME/.scratch.profile
export  COMBINED_PROFILE=$BASH_PROFILE_HOME/.zshrc
export  GENERAL_PROFILE=$BASH_PROFILE_HOME/.general.profile
export  SASHIMIBLADE_PROFILE=$BASH_PROFILE_HOME/.sashimiblade.profile
export  VARIABLES=$BASH_PROFILE_HOME/variables.sh
export  FUNCTIONS=$BASH_PROFILE_HOME/functions.sh

source ~/Dropbox/bash/.colors
source $GENERAL_PROFILE
source $VARIABLES
source $SASHIMIBLADE_PROFILE
source $SCRATCH

alias cpbp "pbcopy < $GENERAL_PROFILE"

