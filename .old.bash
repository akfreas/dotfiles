export PYTHONSTARTUP=~/.pythonrc
export EDITOR=/usr/bin/vim
export MYVIMRC=~/.vimrc
export SVN_EDITOR=/usr/bin/vim

alias ll='ls -Galhs'
alias c='clear'
alias python='bpython'
alias grepr='grep -ril'
alias cdp='cd /Users/alexanderfreas/projects/wpf_maintenance'
alias cp='cp -r'
alias sup='svn up; cp /Users/alexanderfreas/Desktop/shell.py /Users/alexanderfreas/projects/wpf_maintenance/parts/project-content/django/core/management/commands/shell.py; cp /Users/alexanderfreas/Desktop/shell.py /Users/alexanderfreas/projects/wpf_maintenance/parts/project-live/django/core/management/commands/shell.py;' 
alias hf='history | grep '
alias cdb='psql -U ngdm_wpf postgres'
PATH=/usr/local/pgsql/bin/:$PATH
MANPATH=/usr/local/pgsql/man/:$MANPATH

alias va='source /Users/alexanderfreas/django-projects/romanceroulette/bin/activate'
alias vd='deactivate'

export PS1="\\[$(tput bold)\\]\\[$(tput setaf 2)\\]\u @ \W > \\[$(tput sgr0)\\]"

alias ss='ssh ec2-user@107.20.133.133'
