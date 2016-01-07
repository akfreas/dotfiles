mv ~/.bash_profile ~/.bash_profile.bak
ln -s ./bash/.bash_profile ~/.bash_profile

if [ -d "~/Library/Preferences/com.googlecode.iterm2.plist" ];
then
    rm ~/Library/Preferences/com.googlecode.iterm2.plist
    ln -s ./iTerm/com.googlecode.iterm2.plist ~/Library/Preferences/com.googlecode.iterm2.plist
fi

if [ -d "~/Library/Developer/Xcode/UserData" ];
then
    rm -rf ~/Library/Developer/Xcode/UserData
    ln -s ./Xcode/UserData  ~/Library/Developer/Xcode/UserData
fi

mv ~/.vimrc ~/.vimrc-bak
ln -s ./vim ~/.vim
ln -s ./vim/.vimrc ~/.vimrc

mv ~/.gitconfig ~/.gitconfig.bak
ln -s ./git/.gitconfig ~/.gitconfig
