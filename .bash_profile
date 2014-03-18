export DROPBOX_HOME=~/Dropbox
export BASH_PROFILE_HOME=$DROPBOX_HOME/bash
export PATH=/usr/local/bin:$HOME/.rbenv/bin:$PATH

export SCRATCH=$BASH_PROFILE_HOME/.scratch.profile
export COMBINED_PROFILE=$BASH_PROFILE_HOME/.zshrc
export GENERAL_PROFILE=$BASH_PROFILE_HOME/.general.profile
export SASHIMIBLADE_PROFILE=$BASH_PROFILE_HOME/.sashimiblade.profile
export VARIABLES=$BASH_PROFILE_HOME/variables.sh
export FUNCTIONS=$BASH_PROFILE_HOME/functions.sh

source ~/Dropbox/bash/.colors
source $GENERAL_PROFILE
source $VARIABLES
source $SASHIMIBLADE_PROFILE
source $FUNCTIONS
source $SCRATCH

alias cpbp="pbcopy < $GENERAL_PROFILE"

alias ebp='vi -f $COMBINED_PROFILE && source $COMBINED_PROFILE'
alias ebpg='vi -f $GENERAL_PROFILE && source $COMBINED_PROFILE && echo "General profile sourced."'
alias ebpv="vi -f $VARIABLES"
alias ebpf="vi -f $FUNCTIONS"
alias ebpc="vi -f $SCRATCH"
alias ebpt="vi -f $TAXIMAGIC_PROFILE"
alias ebps="vi -f $SASHIMIBLADE_PROFILE"
eval "$(rbenv init -)"

