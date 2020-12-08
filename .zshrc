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


export PATH=/usr/local/bin:/bin:/usr/sbin:/sbin:/usr/bin:/opt/X11/bin:
export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"
source $ZSH/oh-my-zsh.sh

# Customize to your needs...
export BASH_PROFILE_HOME=$HOME/dotfiles
export LANG=en_US.UTF-8

export COMBINED_PROFILE=$BASH_PROFILE_HOME/.bash_profile
export GENERAL_PROFILE=$BASH_PROFILE_HOME/.general.profile
export SASHIMIBLADE_PROFILE=$BASH_PROFILE_HOME/.sashimiblade.profile
export VARIABLES=$BASH_PROFILE_HOME/variables.sh
export FUNCTIONS=$BASH_PROFILE_HOME/functions.sh
source .bashrc 2> /dev/null
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

alias vi='vim'
alias bpython="nocorrect bpython"
alias knife="nocorrect knife"
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"
export WORKON_HOME=$HOME/.virtualenvs
export PROJECT_HOME=$HOME/Devel
export VIRTUALENVWRAPPER_SCRIPT=/usr/local/bin/virtualenvwrapper.sh
source /usr/local/bin/virtualenvwrapper_lazy.sh

export DIFF_OPTIONS=-u

#unsetopt correct_all



PATH="/home/alex/perl5/bin${PATH+:}${PATH}"; export PATH;
PERL5LIB="/home/alex/perl5/lib/perl5${PERL5LIB+:}${PERL5LIB}"; export PERL5LIB;
PERL_LOCAL_LIB_ROOT="/home/alex/perl5${PERL_LOCAL_LIB_ROOT+:}${PERL_LOCAL_LIB_ROOT}"; export PERL_LOCAL_LIB_ROOT;
PERL_MB_OPT="--install_base \"/home/alex/perl5\""; export PERL_MB_OPT;
PERL_MM_OPT="INSTALL_BASE=/home/alex/perl5"; export PERL_MM_OPT;

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

export PS1='$(f_notifyme)'$PS1

export GOPATH="$HOME/go"
export PATH="/usr/local/go/bin:$PATH"
export PATH="$HOME/.fastlane/bin:$PATH"
export PATH="code:$PATH"

alias less=$PAGER -i -R
LESS="-i -R";
export LESS;
alias zless=$PAGER
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
ANDROID_HOME="/Users/afreas/Library/Android/sdk"

#export NVM_DIR=~/.nvm
#source $(brew --prefix nvm)/nvm.sh #takes many seconds to start, not worth it!

#export NVM_DIR="$HOME/.nvm"
#export PATH="/Users/afreas/.pyenv/bin:$PATH"
#eval "$(pyenv init -)"
#eval "$(pyenv virtualenv-init -)"
#[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
#[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# tabtab source for serverless package
# uninstall by removing these lines or running `tabtab uninstall serverless`
#[[ -f /usr/local/lib/node_modules/serverless/node_modules/tabtab/.completions/serverless.zsh ]] && . /usr/local/lib/node_modules/serverless/node_modules/tabtab/.completions/serverless.zsh
# tabtab source for sls package
# uninstall by removing these lines or running `tabtab uninstall sls`
#[[ -f /usr/local/lib/node_modules/serverless/node_modules/tabtab/.completions/sls.zsh ]] && . /usr/local/lib/node_modules/serverless/node_modules/tabtab/.completions/sls.zsh

# tabtab source for slss package
# uninstall by removing these lines or running `tabtab uninstall slss`
#[[ -f /Users/afreas/github/MobileTestUtils/node_modules/tabtab/.completions/slss.zsh ]] && . /Users/afreas/github/MobileTestUtils/node_modules/tabtab/.completions/slss.zsh
