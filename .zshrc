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
export PATH="/usr/local/opt/python/libexec/bin:$PATH"
export PATH="$PATH:/Applications/Docker.app/Contents/Resources/bin/"
export PYTHONPATH=/usr/local/lib/python3.10/site-packages
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

alias vi='vim'
alias bpython="nocorrect bpython"
alias knife="nocorrect knife"
# rbenv: shims on PATH immediately; defer full init (rehash/hooks/completion) to first use
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
rbenv() { unset -f rbenv; eval "$(command rbenv init -)"; rbenv "$@"; }
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

LESS="-i -R";
export LESS;

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Source forgit plugin (requires fzf)
[ -f /opt/homebrew/opt/forgit/share/forgit/forgit.plugin.zsh ] && source /opt/homebrew/opt/forgit/share/forgit/forgit.plugin.zsh
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/platform-tools

# pyenv: shims on PATH immediately; defer full init to first use
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/shims:$PATH"
pyenv() { unset -f pyenv; eval "$(command pyenv init - zsh)"; pyenv "$@"; }

PATH=$PATH:~/.composer/vendor/bin

export PATH="/opt/homebrew/bin:$PATH"
export NVM_DIR="$HOME/.nvm"
# Lazy-load nvm on first use of nvm/node/npm/npx to keep shell startup fast
_load_nvm() {
  unset -f nvm node npm npx _load_nvm
  [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"
  [ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"
}
nvm()  { _load_nvm; nvm "$@"; }
node() { _load_nvm; node "$@"; }
npm()  { _load_nvm; npm "$@"; }
npx()  { _load_nvm; npx "$@"; }
export PATH="$HOME/.pyenv/bin:$PATH"


#export JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home
#export PATH=$JAVA_HOME/bin:$PATH

# Created by `pipx` on 2024-07-16 06:34:52

export WORKON_HOME=$HOME/.virtualenvs
export PROJECT_HOME=$HOME/Devel
# Lazy-load virtualenvwrapper on first use of one of its commands
_load_virtualenvwrapper() {
  unset -f workon mkvirtualenv rmvirtualenv mkproject lsvirtualenv allvirtualenv _load_virtualenvwrapper
  source virtualenvwrapper.sh
}
for _vew_cmd in workon mkvirtualenv rmvirtualenv mkproject lsvirtualenv allvirtualenv; do
  eval "${_vew_cmd}() { _load_virtualenvwrapper; ${_vew_cmd} \"\$@\"; }"
done
unset _vew_cmd
# jenv: shims on PATH immediately; defer full init (hooks/completion) to first use
export PATH="$HOME/.jenv/bin:$HOME/.jenv/shims:$PATH"
jenv() { unset -f jenv; eval "$(command jenv init -)"; jenv "$@"; }

# >>> conda initialize >>>
# Lazy-load conda on first use; avoids running the hook and activating base on every shell
__lazy_conda() {
    unset -f conda __lazy_conda
    __conda_setup="$('/opt/anaconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
    if [ $? -eq 0 ]; then
        eval "$__conda_setup"
    elif [ -f "/opt/anaconda3/etc/profile.d/conda.sh" ]; then
        . "/opt/anaconda3/etc/profile.d/conda.sh"
    else
        export PATH="/opt/anaconda3/bin:$PATH"
    fi
    unset __conda_setup
}
conda() { __lazy_conda; conda "$@"; }
# <<< conda initialize <<<


# Added by Windsurf
export PATH="$HOME/.local/bin:$PATH"
export JAVA_HOME="/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_HOME="/Users/alexander.freas/Library/Android/sdk"
export ANDROID_SDK_ROOT="/Users/alexander.freas/Library/Android/sdk"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
