export DROPBOX_HOME=~/Google\ Drive

ruby -e "$(curl -fsSkL raw.github.com/mxcl/homebrew/go)"

mv ~/.bash_profile ~/.bash_profile.bak
ln -s $DROPBOX_HOME/bash/.bash_profile ~/.bash_profile

rm ~/Library/Preferences/com.googlecode.iterm2.plist
ln -s $DROPBOX_HOME/iTerm/com.googlecode.iterm2.plist ~/Library/Preferences/com.googlecode.iterm2.plist

rm -rf ~/Library/Developer/Xcode/UserData
ln -s $DROPBOX_HOME/Xcode/UserData  ~/Library/Developer/Xcode/UserData

mv ~/Library/StickiesDatabase ~/StickiesDatabaseBackup
ln -s $DROPBOX_HOME/StickiesDatabase ~/Library/StickiesDatabase

mv ~/.vimrc ~/.vimrc-bak
ln -s $DROPBOX_HOME/vim ~/.vim
ln -s $DROPBOX_HOME/vim/.vimrc ~/.vimrc

mv ~/.gitconfig ~/.gitconfig.bak
ln -s $DROPBOX_HOME/git/.gitconfig ~/.gitconfig
