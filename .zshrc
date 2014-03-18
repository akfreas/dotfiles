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
plugins=(cap gem git github knife perl vagrant)


export PATH=/usr/local/bin:/bin:/usr/sbin:/sbin:/usr/bin:/opt/X11/bin:
source $ZSH/oh-my-zsh.sh

# Customize to your needs...
export DROPBOX_HOME=~/Dropbox
export BASH_PROFILE_HOME=$DROPBOX_HOME/bash

export SCRATCH=$BASH_PROFILE_HOME/.scratch.profile
export COMBINED_PROFILE=$BASH_PROFILE_HOME/.bash_profile
export TAXIMAGIC_PROFILE=$BASH_PROFILE_HOME/.taximagic_profile
export GENERAL_PROFILE=$BASH_PROFILE_HOME/.general.profile
export SASHIMIBLADE_PROFILE=$BASH_PROFILE_HOME/.sashimiblade.profile
export CARPE_PROFILE=$BASH_PROFILE_HOME/.carpe.profile
export VARIABLES=$BASH_PROFILE_HOME/variables.sh
export FUNCTIONS=$BASH_PROFILE_HOME/functions.sh

source ~/Dropbox/bash/.colors
source $GENERAL_PROFILE
source $TAXIMAGIC_PROFILE
source $CARPE_PROFILE
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
eval "$(rbenv init -)"
PATH=$HOME/.rbenv/shims:$PATH



#PROMPT='[${_t}]${_u}@${_h} [${_red}$(git_prompt_info)${_rc} ${_red}$(git_prompt_short_sha)${_rc}] [${_magenta}$(rbenv_prompt_info)${_rc}] ${_v}
#${_p}
#'
#
#PROMPT='%{$fg_bold[red]%}➜ %{$fg_bold[green]%}%p %{$fg[cyan]%}%c %{$fg_bold[blue]%} [${_magenta}$(rbenv_prompt_info)${_rc}]  %{$(git_prompt_info)%{$fg_bold[blue]%}% %{$reset_color%} ${_v}'
#PROMPT='%{$fg_bold[green]%}➜ %{$fg_bold[green]%}%p %{$fg[cyan]%}%c %{$fg_bold[blue]%} [${_magenta}$(rbenv_prompt_info)%{$_blue%}]%{$_rc%}  %{$fg_bold[blue]%}%{$(git_prompt_info)%{$_rc%} '


#export EDITOR=emacs
export DIFF_OPTIONS=-u
export MYSQL_PS1="\v \u@\h:\p (\d)>"

#unsetopt correct_all


### Added by the Heroku Toolbelt
export PATH="/usr/local/heroku/bin:$PATH"

# added by travis gem
source /Users/akfreas/.travis/travis.sh
