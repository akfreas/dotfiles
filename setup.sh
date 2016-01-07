SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )
echo $SCRIPTPATH

mv ~/.bash_profile ~/.bash_profile.bak
ln -s $SCRIPTPATH/.zshrc ~/.bash_profile

if [ -d "~/Library/Preferences/com.googlecode.iterm2.plist" ];
then
    rm ~/Library/Preferences/com.googlecode.iterm2.plist
    ln -s $SCRIPTPATH/iTerm/com.googlecode.iterm2.plist ~/Library/Preferences/com.googlecode.iterm2.plist
fi

if [ -d "~/Library/Developer/Xcode/UserData" ];
then
    rm -rf ~/Library/Developer/Xcode/UserData
    ln -s $SCRIPTPATH/Xcode/UserData  ~/Library/Developer/Xcode/UserData
fi

mv ~/.vimrc ~/.vimrc-bak
ln -s $SCRIPTPATH/.vimrc ~/.vimrc

mv ~/.gitconfig ~/.gitconfig.bak
ln -s $SCRIPTPATH/git/.gitconfig ~/.gitconfig

mkdir -p ~/.vim/autoload ~/.vim/bundle && \
curl -LSso ~/.vim/autoload/pathogen.vim https://tpo.pe/pathogen.vim


cd ~/.vim/bundle
git clone git://github.com/tpope/vim-bundler.git


git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
wget -O - https://raw.githubusercontent.com/nvbn/thefuck/master/install.sh | sh - && $0

unamestr=`uname`
if [[ "$unamestr" == 'Linux' ]]; then

    sudo apt-get install cmake
    sudo apt-get install ruby ruby-dev libncurses5-dev mercurial build-essential rake

    hg clone https://vim.googlecode.com/hg/ vim
    cd vim
    ./configure --with-features=huge --enable-rubyinterp --enable-pythoninterp --prefix=$HOME
    make
    sudo make install



elif [[ "$unamestr" == 'Darwin' ]]; then
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
fi
