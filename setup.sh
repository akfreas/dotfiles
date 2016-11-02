SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )
echo $SCRIPTPATH


if [ -d "~/Library/Preferences/com.googlecode.iterm2.plist" ];
then
    rm ~/Library/Preferences/com.googlecode.iterm2.plist
    ln -s $SCRIPTPATH/com.googlecode.iterm2.plist ~/Library/Preferences/com.googlecode.iterm2.plist
fi

if [ -d "~/Library/Developer/Xcode/UserData" ];
then
    rm -rf ~/Library/Developer/Xcode/UserData
    ln -s $SCRIPTPATH/Xcode/UserData  ~/Library/Developer/Xcode/UserData
fi

mv ~/.vimrc ~/.vimrc-bak
ln -s $SCRIPTPATH/.vimrc ~/.vimrc

mv ~/.gitconfig ~/.gitconfig.bak
ln -s $SCRIPTPATH/gitfiles/.gitconfig ~/.gitconfig

mkdir -p ~/.vim/autoload ~/.vim/bundle && \
curl -LSso ~/.vim/autoload/pathogen.vim https://tpo.pe/pathogen.vim


cd ~/.vim/bundle
git clone git://github.com/tpope/vim-bundler.git


git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim

unamestr=`uname`
if [[ "$unamestr" == 'Linux' ]]; then

    sudo apt-get remove --yes vim vim-runtime gvim vim-tiny vim-common vim-gui-common vim-nox


    cat $SCRIPTPATH/apt-packages.txt | xargs sudo apt-get --yes --force-yes install

    cd ~
    git clone https://github.com/vim/vim.git
    cd vim
    ./configure --with-features=huge \
                --enable-multibyte \
                --enable-rubyinterp \
                --enable-pythoninterp \
                --with-python-config-dir=/usr/lib/python2.7/config \
                --enable-python3interp \
                --with-python3-config-dir=/usr/lib/python3.5/config \
                --enable-perlinterp \
                --enable-luainterp \
                --enable-gui=gtk2 --enable-cscope --prefix=/usr
    make VIMRUNTIMEDIR=/usr/share/vim/vim74
    sudo make install
    cd ~
    sudo checkinstall
    sudo update-alternatives --install /usr/bin/editor editor /usr/bin/vim 1
    sudo update-alternatives --set editor /usr/bin/vim
    sudo update-alternatives --install /usr/bin/vi vi /usr/bin/vim 1
    sudo update-alternatives --set vi /usr/bin/vim

    TEMP_PAM=`mktemp`; echo "auth       sufficient   pam_wheel.so trust group=chsh" | cat - /etc/pam.d/chsh >  $TEMP_PAM && sudo mv $TEMP_PAM /etc/pam.d/chsh
    sudo groupadd chsh
    usermod -a -G chsh `whoami`
    chsh -s `which zsh`
#    wget https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh -O - | zsh


    # Docker setup

    sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
    echo "deb https://apt.dockerproject.org/repo ubuntu-trusty main" >  /etc/apt/sources.list.d/docker.list
    sudo apt-cache policy docker-engine
    sudo apt-get update
    sudo apt-get install --yes docker-engine 
    sudo usermod -aG docker ubuntu
    sudo service docker start



elif [[ "$unamestr" == 'Darwin' ]]; then
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    wget https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh -O - | zsh
    sudo chsh -s `which zsh` `whoami`
    brew install cmake \
        wget ruby-build \
        vim tree \
        rbenv thefuck docker-machine
    sudo xcode-select --install
fi

# Install Vim Plugins

vim -c BundleInstall -c quitall
cd ~/.vim/bundle/YouCompleteMe
./install.py --clang-completer

# Pip Install
curl https://bootstrap.pypa.io/get-pip.py | sudo python
sudo pip install virtualenvwrapper

# Docker Compose

curl -L https://github.com/docker/compose/releases/download/1.7.1/docker-compose-`uname -s`-`uname -m` > ./docker-compose
sudo mv docker-compose /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

mv ~/.bash_profile ~/.bash_profile.bak
ln -s $SCRIPTPATH/.zshrc ~/.bash_profile


mv ~/.zshrc ~/.zshrc.bak
ln -s $SCRIPTPATH/.zshrc ~/.zshrc
