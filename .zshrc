# Path to your oh-my-zsh configuration.
ZSH=$HOME/.oh-my-zsh

# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
# Optionally, if you set this to "random", it'll load a random theme each
# time that oh-my-zsh is loaded.
ZSH_THEME="robbyrussell"

# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# Set to this to use case-sensitive completion
# CASE_SENSITIVE="true"

# Comment this out to disable weekly auto-update checks
# DISABLE_AUTO_UPDATE="true"

# Uncomment following line if you want to disable colors in ls
# DISABLE_LS_COLORS="true"

# Uncomment following line if you want to disable autosetting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment following line if you want red dots to be displayed while waiting for completion
# COMPLETION_WAITING_DOTS="true"

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
#plugins=(cap gem git github knife perl vagrant)

alias vi=vim

export PATH=/usr/local/bin:/bin:/usr/sbin:/sbin:/usr/bin:/opt/X11/bin:
source $ZSH/oh-my-zsh.sh

# Customize to your needs...
export BASH_PROFILE_HOME=$HOME/dotfiles
export LANG=en_US.UTF-8

export COMBINED_PROFILE=$BASH_PROFILE_HOME/.bash_profile
export GENERAL_PROFILE=$BASH_PROFILE_HOME/.general.profile
export SASHIMIBLADE_PROFILE=$BASH_PROFILE_HOME/.sashimiblade.profile
export VARIABLES=$BASH_PROFILE_HOME/variables.sh
export FUNCTIONS=$BASH_PROFILE_HOME/functions.sh

source $HOME/dotfiles/.colors
source $GENERAL_PROFILE
source $VARIABLES
source $SASHIMIBLADE_PROFILE
source $FUNCTIONS

alias cpbp="pbcopy < $GENERAL_PROFILE"

alias ebp='vi -f $COMBINED_PROFILE && source $COMBINED_PROFILE'
alias ebpg='vi -f $GENERAL_PROFILE && source $COMBINED_PROFILE && echo "General profile sourced."'
alias ebpv="vi -f $VARIABLES"
alias ebpf="vi -f $FUNCTIONS"
alias ebps="vi -f $SASHIMIBLADE_PROFILE"

_red="%{$fg[red]%}"
_yellow="%{$fg[yellow]%}"
_green="%{$fg[green]%}"
_blue="%{$fg[blue]%}"
_cyan="%{$fg[cyan]%}"
_magenta="%{$fg[magenta]%}"
_black="%{$fg[black]%}"
_white="%{$fg[white]%}"
_rc="%{$reset_color%}"

_t="${_cyan}%l${_rc}"
_u="${_cyan}%n${_rc}"
_h="${_yellow}%M${_rc}"
_p="${_green}%/${_rc}"
_v="rv=%?"

alias bpython="nocorrect bpython"
alias knife="nocorrect knife"
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"
eval "$(thefuck --alias)"
export WORKON_HOME=$HOME/.virtualenvs
export PROJECT_HOME=$HOME/Devel
source /usr/local/bin/virtualenvwrapper.sh



#export EDITOR=emacs
export DIFF_OPTIONS=-u

#unsetopt correct_all



PATH="/home/alex/perl5/bin${PATH+:}${PATH}"; export PATH;
PERL5LIB="/home/alex/perl5/lib/perl5${PERL5LIB+:}${PERL5LIB}"; export PERL5LIB;
PERL_LOCAL_LIB_ROOT="/home/alex/perl5${PERL_LOCAL_LIB_ROOT+:}${PERL_LOCAL_LIB_ROOT}"; export PERL_LOCAL_LIB_ROOT;
PERL_MB_OPT="--install_base \"/home/alex/perl5\""; export PERL_MB_OPT;
PERL_MM_OPT="INSTALL_BASE=/home/alex/perl5"; export PERL_MM_OPT;


