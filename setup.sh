set -e
SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Status functions
print_step() {
    echo -e "${BLUE}🔵 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

echo -e "${PURPLE}🚀 Starting dotfiles setup...${NC}"
echo -e "${CYAN}📁 Script path: $SCRIPTPATH${NC}"
echo ""


print_step "Setting up iTerm2 preferences..."
if [ -d "~/Library/Preferences/com.googlecode.iterm2.plist" ];
then
    rm ~/Library/Preferences/com.googlecode.iterm2.plist
    ln -s $SCRIPTPATH/com.googlecode.iterm2.plist ~/Library/Preferences/com.googlecode.iterm2.plist
    print_success "iTerm2 preferences linked"
else
    print_info "iTerm2 preferences directory not found, skipping"
fi

print_step "Setting up Xcode preferences..."
if [ -d "~/Library/Developer/Xcode/UserData" ];
then
    rm -rf ~/Library/Developer/Xcode/UserData
    ln -s $SCRIPTPATH/Xcode/UserData  ~/Library/Developer/Xcode/UserData
    print_success "Xcode preferences linked"
else
    print_info "Xcode UserData directory not found, skipping"
fi

print_step "Setting up Vim configuration..."
mv ~/.vimrc ~/.vimrc-bak || true
ln -s $SCRIPTPATH/.vimrc ~/.vimrc
print_success "Vim configuration linked"

print_step "Setting up Git configuration..."
mv ~/.gitconfig ~/.gitconfig.bak || true
ln -s $SCRIPTPATH/gitfiles/.gitconfig ~/.gitconfig
print_success "Git configuration linked"

print_step "Installing Vim Pathogen..."
mkdir -p ~/.vim/autoload ~/.vim/bundle && \
curl -LSso ~/.vim/autoload/pathogen.vim https://tpo.pe/pathogen.vim
print_success "Pathogen installed"

print_step "Installing Vim plugins..."
cd ~/.vim/bundle
if [ ! -d "./vim-bundler" ];
then
    print_info "Cloning vim-bundler..."
    git clone https://github.com/tpope/vim-bundler.git
    print_success "vim-bundler installed"
else
    print_info "vim-bundler already installed"
fi;

if [ ! -d "./Vundle.vim" ];
then
    print_info "Cloning Vundle.vim..."
    git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
    print_success "Vundle.vim installed"
else
    print_info "Vundle.vim already installed"
fi

unamestr=`uname`
if [[ "$unamestr" == 'Linux' ]]; then
    echo ""
    print_step "🐧 Detected Linux system - starting Linux-specific setup..."
    
    print_step "Removing old Vim packages..."
    sudo apt-get remove --yes vim vim-runtime gvim vim-tiny vim-common vim-gui-common vim-nox
    print_success "Old Vim packages removed"

    print_step "Installing apt packages..."
    cat $SCRIPTPATH/apt-packages.txt | xargs sudo apt-get --yes --force-yes install
    print_success "APT packages installed"

    print_step "Compiling Vim from source..."
    cd ~
    git clone https://github.com/vim/vim.git
    cd vim
    print_info "Configuring Vim..."
    ./configure --with-features=huge \
                --enable-multibyte \
                --enable-rubyinterp \
                --enable-pythoninterp \
                --enable-python3interp \
                --with-python3-config-dir=/usr/lib/python3.7/config-3.7m-x86_64-linux-gnu \
                --with-python3-config-dir=/usr/lib/python3.5/config \
                --enable-perlinterp \
                --enable-luainterp \
                --enable-gui=gtk2 --enable-cscope --prefix=/usr
    print_info "Building Vim (this may take a while)..."
    make VIMRUNTIMEDIR=/usr/share/vim/vim74
    print_info "Installing Vim..."
    sudo make install
    cd ~
    sudo checkinstall
    print_success "Vim compiled and installed"
    
    print_step "Configuring Vim as default editor..."
    sudo update-alternatives --install /usr/bin/editor editor /usr/bin/vim 1
    sudo update-alternatives --set editor /usr/bin/vim
    sudo update-alternatives --install /usr/bin/vi vi /usr/bin/vim 1
    sudo update-alternatives --set vi /usr/bin/vim
    print_success "Vim set as default editor"

    print_step "Configuring ZSH as default shell..."
    TEMP_PAM=`mktemp`; echo "auth       sufficient   pam_wheel.so trust group=chsh" | cat - /etc/pam.d/chsh >  $TEMP_PAM && sudo mv $TEMP_PAM /etc/pam.d/chsh
    sudo groupadd chsh
    usermod -a -G chsh `whoami`
    chsh -s `which zsh`
    print_success "ZSH configured as default shell"

    print_step "Setting up Docker..."
    sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
    echo "deb https://apt.dockerproject.org/repo ubuntu-trusty main" >  /etc/apt/sources.list.d/docker.list
    sudo apt-cache policy docker-engine
    sudo apt-get update
    print_info "Installing Docker engine..."
    sudo apt-get install --yes docker-engine 
    sudo usermod -aG docker ubuntu
    sudo service docker start
    print_success "Docker installed and started"



elif [[ "$unamestr" == 'Darwin' ]]; then
    echo ""
    print_step "🍎 Detected macOS system - starting macOS-specific setup..."
    
    print_step "Checking for Homebrew..."
    if ! brew -v; then
        print_info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
        print_success "Homebrew installed"
    else
        print_success "Homebrew already installed"
    fi
    
    print_step "Setting up Oh-My-Zsh..."
    if [ ! -d "$HOME/.oh-my-zsh" ];
    then
        print_info "Installing Oh-My-Zsh..."
        wget https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh -O - | zsh
        print_success "Oh-My-Zsh installed"
    else
        print_info "Oh-My-Zsh already installed"
    fi
    
    print_step "Configuring ZSH as default shell..."
    sudo chsh -s `which zsh` `whoami`
    print_success "ZSH configured"
    
    print_step "Installing Homebrew packages..."
    brew install cmake \
        wget ruby-build \
        vim tree \
        rbenv fzf forgit pip3 pipx python@3
    print_success "Homebrew packages installed"
    
    print_step "Checking for Xcode Command Line Tools..."
    if ! xcode-select -v; then
        print_info "Installing Xcode Command Line Tools..."
        sudo xcode-select --install
        print_success "Xcode Command Line Tools installed"
    else
        print_success "Xcode Command Line Tools already installed"
    fi
fi

print_step "Installing fzf key bindings and fuzzy completion..."
yes | $(brew --prefix)/opt/fzf/install
print_success "fzf key bindings installed"

print_step "Installing Vim plugins with Vundle..."
vim -c BundleInstall -c quitall
print_success "Vim plugins installed"

print_step "Building YouCompleteMe..."
cd ~/.vim/bundle/YouCompleteMe
./install.py --clang-completer
print_success "YouCompleteMe built"

print_step "Installing vimpager..."
cd `mktemp -d`
git clone https://github.com/rkitover/vimpager
cd vimpager
sudo make install
print_success "vimpager installed"


print_step "Installing Python virtualenvwrapper..."
sudo pip3 install virtualenvwrapper
print_success "virtualenvwrapper installed"

print_step "Setting up shell profiles..."
mv ~/.bash_profile ~/.bash_profile.bak || true
ln -s $SCRIPTPATH/.zshrc ~/.bash_profile
print_info "bash_profile linked"

print_step "Installing Cursor..."
curl https://cursor.com/install -fsS | bash
print_success "Cursor installed"

mv ~/.zshrc ~/.zshrc.bak || true
ln -s $SCRIPTPATH/.zshrc ~/.zshrc
print_success "Shell profiles configured"

cd -

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  🎉  Setup completed successfully!  🎉                       ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
print_info "Please restart your terminal or run 'source ~/.zshrc' to apply changes"
echo ""
