# Don't exit on error - we want to continue and report all errors at the end
set +e
SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Error tracking
declare -a ERRORS=()
declare -a WARNINGS=()
CURRENT_STEP=""

# Status functions
print_step() {
    CURRENT_STEP="$1"
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
    WARNINGS+=("$1")
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    ERRORS+=("$CURRENT_STEP: $1")
}

# Run command and track errors
run_cmd() {
    "$@"
    local status=$?
    if [ $status -ne 0 ]; then
        print_error "Command failed with exit code $status: $*"
        return $status
    fi
    return 0
}

# Check last command status and report error if failed
check_status() {
    local status=$?
    local msg="$1"
    if [ $status -ne 0 ]; then
        print_error "$msg (exit code: $status)"
        return 1
    fi
    return 0
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
mkdir -p ~/.vim/autoload ~/.vim/bundle
curl -LSso ~/.vim/autoload/pathogen.vim https://tpo.pe/pathogen.vim
if [ $? -eq 0 ]; then
    print_success "Pathogen installed"
else
    print_error "Failed to install Pathogen"
fi

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
    if [ $? -eq 0 ]; then
        print_success "APT packages installed"
    else
        print_error "Failed to install some APT packages"
    fi

    print_step "Compiling Vim from source..."
    cd ~
    if git clone https://github.com/vim/vim.git && cd vim; then
        print_info "Configuring Vim..."
        if ./configure --with-features=huge \
                    --enable-multibyte \
                    --enable-rubyinterp \
                    --enable-pythoninterp \
                    --enable-python3interp \
                    --with-python3-config-dir=/usr/lib/python3.7/config-3.7m-x86_64-linux-gnu \
                    --with-python3-config-dir=/usr/lib/python3.5/config \
                    --enable-perlinterp \
                    --enable-luainterp \
                    --enable-gui=gtk2 --enable-cscope --prefix=/usr; then
            print_info "Building Vim (this may take a while)..."
            if make VIMRUNTIMEDIR=/usr/share/vim/vim74; then
                print_info "Installing Vim..."
                if sudo make install; then
                    cd ~
                    sudo checkinstall || print_warning "checkinstall failed, but Vim was installed"
                    print_success "Vim compiled and installed"
                else
                    print_error "Failed to install Vim"
                fi
            else
                print_error "Failed to build Vim"
            fi
        else
            print_error "Failed to configure Vim"
        fi
    else
        print_error "Failed to clone Vim repository"
    fi
    
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
    if sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D; then
        echo "deb https://apt.dockerproject.org/repo ubuntu-trusty main" >  /etc/apt/sources.list.d/docker.list
        sudo apt-cache policy docker-engine
        sudo apt-get update
        print_info "Installing Docker engine..."
        if sudo apt-get install --yes docker-engine; then
            sudo usermod -aG docker ubuntu
            sudo service docker start
            print_success "Docker installed and started"
        else
            print_error "Failed to install Docker engine"
        fi
    else
        print_error "Failed to add Docker repository key"
    fi



elif [[ "$unamestr" == 'Darwin' ]]; then
    echo ""
    print_step "🍎 Detected macOS system - starting macOS-specific setup..."
    
    print_step "Checking for Homebrew..."
    if ! brew -v 2>/dev/null; then
        print_info "Installing Homebrew..."
        if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"; then
            print_success "Homebrew installed"
        else
            print_error "Failed to install Homebrew"
        fi
    else
        print_success "Homebrew already installed"
    fi
    
    print_step "Setting up Oh-My-Zsh..."
    if [ ! -d "$HOME/.oh-my-zsh" ];
    then
        print_info "Installing Oh-My-Zsh..."
        if wget https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh -O - | zsh; then
            print_success "Oh-My-Zsh installed"
        else
            print_error "Failed to install Oh-My-Zsh"
        fi
    else
        print_info "Oh-My-Zsh already installed"
    fi
    
    print_step "Configuring ZSH as default shell..."
    if sudo chsh -s `which zsh` `whoami`; then
        print_success "ZSH configured"
    else
        print_error "Failed to configure ZSH as default shell"
    fi
    
    print_step "Installing Homebrew packages..."
    brew install cmake \
        wget ruby-build \
        vim tree \
        rbenv fzf forgit pipx python@3
    if [ $? -eq 0 ]; then
        print_success "Homebrew packages installed"
    else
        print_error "Failed to install some Homebrew packages"
    fi
    
    print_step "Checking for Xcode Command Line Tools..."
    if ! xcode-select -v 2>/dev/null; then
        print_info "Installing Xcode Command Line Tools..."
        if sudo xcode-select --install; then
            print_success "Xcode Command Line Tools installed"
        else
            print_warning "Xcode Command Line Tools installation may require manual intervention"
        fi
    else
        print_success "Xcode Command Line Tools already installed"
    fi
fi

print_step "Installing fzf key bindings and fuzzy completion..."
yes | $(brew --prefix)/opt/fzf/install
if [ $? -eq 0 ]; then
    print_success "fzf key bindings installed"
else
    print_error "Failed to install fzf key bindings"
fi

print_step "Installing Vim plugins with Vundle..."
vim -c BundleInstall -c quitall
if [ $? -eq 0 ]; then
    print_success "Vim plugins installed"
else
    print_error "Failed to install Vim plugins"
fi

print_step "Building YouCompleteMe..."
if [ -d ~/.vim/bundle/YouCompleteMe ]; then
    cd ~/.vim/bundle/YouCompleteMe
    ./install.py --clang-completer
    if [ $? -eq 0 ]; then
        print_success "YouCompleteMe built"
    else
        print_error "Failed to build YouCompleteMe"
    fi
else
    print_warning "YouCompleteMe directory not found, skipping build"
fi

print_step "Installing vimpager..."
VIMPAGER_DIR=`mktemp -d`
cd "$VIMPAGER_DIR"
if git clone https://github.com/rkitover/vimpager && cd vimpager && sudo make install; then
    print_success "vimpager installed"
else
    print_error "Failed to install vimpager"
fi

print_step "Installing Python virtualenvwrapper..."
sudo pip3 install virtualenvwrapper
if [ $? -eq 0 ]; then
    print_success "virtualenvwrapper installed"
else
    print_error "Failed to install virtualenvwrapper"
fi

print_step "Setting up shell profiles..."
mv ~/.bash_profile ~/.bash_profile.bak || true
ln -s $SCRIPTPATH/.zshrc ~/.bash_profile
print_info "bash_profile linked"

print_step "Installing Cursor..."
curl https://cursor.com/install -fsS | bash
if [ $? -eq 0 ]; then
    print_success "Cursor installed"
else
    print_error "Failed to install Cursor"
fi

mv ~/.zshrc ~/.zshrc.bak || true
ln -s $SCRIPTPATH/.zshrc ~/.zshrc
print_success "Shell profiles configured"

cd -

echo ""
echo "════════════════════════════════════════════════════════════════"
echo ""

# Display summary
if [ ${#ERRORS[@]} -eq 0 ]; then
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                              ║${NC}"
    echo -e "${GREEN}║  🎉  Setup completed successfully!  🎉                       ║${NC}"
    echo -e "${GREEN}║                                                              ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
else
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                                                              ║${NC}"
    echo -e "${YELLOW}║  ⚠️   Setup completed with errors  ⚠️                        ║${NC}"
    echo -e "${YELLOW}║                                                              ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
fi

echo ""

# Show warnings if any
if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠️  WARNINGS (${#WARNINGS[@]}):${NC}"
    echo -e "${YELLOW}────────────────────────────────────────────────────────────${NC}"
    for warning in "${WARNINGS[@]}"; do
        echo -e "${YELLOW}  • $warning${NC}"
    done
    echo ""
fi

# Show errors if any
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo -e "${RED}❌ ERRORS (${#ERRORS[@]}):${NC}"
    echo -e "${RED}────────────────────────────────────────────────────────────${NC}"
    for error in "${ERRORS[@]}"; do
        echo -e "${RED}  • $error${NC}"
    done
    echo ""
    echo -e "${YELLOW}💡 Please review and fix the errors above, then re-run this script.${NC}"
    echo ""
else
    print_info "Please restart your terminal or run 'source ~/.zshrc' to apply changes"
    echo ""
fi

# Exit with error code if there were errors
if [ ${#ERRORS[@]} -gt 0 ]; then
    exit 1
else
    exit 0
fi
