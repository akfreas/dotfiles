set -x BASH_PROFILE_HOME $HOME/dotfiles
set -x PATH /usr/local/bin:$HOME/.rbenv/bin:$PATH

set -x SCRATCH $BASH_PROFILE_HOME/.scratch.profile
set -x COMBINED_PROFILE $BASH_PROFILE_HOME/.zshrc
set -x GENERAL_PROFILE $BASH_PROFILE_HOME/.general.profile
set -x SASHIMIBLADE_PROFILE $BASH_PROFILE_HOME/.sashimiblade.profile
set -x VARIABLES $BASH_PROFILE_HOME/variables.sh
set -x FUNCTIONS $BASH_PROFILE_HOME/functions.sh

source ~/Dropbox/bash/.colors
source $GENERAL_PROFILE
source $VARIABLES
source $SASHIMIBLADE_PROFILE
source $SCRATCH

alias cpbp "pbcopy < $GENERAL_PROFILE"

# Path to your oh-my-fish.
set fish_path $HOME/.oh-my-fish

# Theme
set fish_theme robbyrussell

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-fish/plugins/*)
# Custom plugins may be added to ~/.oh-my-fish/custom/plugins/
# Example format: set fish_plugins autojump bundler

# Path to your custom folder (default path is $FISH/custom)
#set fish_custom $HOME/dotfiles/oh-my-fish

# Load oh-my-fish configuration.
. $fish_path/oh-my-fish.fish
