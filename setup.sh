#!/usr/bin/env bash
#
# dotfiles setup
#
# Remote (fresh machine, nothing installed):
#   curl -fsSL https://raw.githubusercontent.com/akfreas/dotfiles/master/setup.sh | bash
#
# Local (repo already cloned):
#   ./setup.sh
#
# Override the clone location with DOTFILES_DIR, the source with DOTFILES_REPO.
# Note that .zshrc hardcodes $HOME/dotfiles, so moving the repo needs a matching edit there.

# Don't exit on error - we want to continue and report all errors at the end
set +e

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/akfreas/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

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

# Symlink $2 -> $1, backing up whatever was already there.
link_file() {
    local src="$1"
    local dest="$2"

    if [ ! -e "$src" ]; then
        print_warning "Nothing to link, source missing: $src"
        return 1
    fi

    mkdir -p "$(dirname "$dest")"

    if [ -L "$dest" ]; then
        if [ "$(readlink "$dest")" = "$src" ]; then
            print_info "Already linked: $dest"
            return 0
        fi
        rm -f "$dest"
    elif [ -e "$dest" ]; then
        mv "$dest" "$dest.bak.$TIMESTAMP"
        print_info "Backed up $dest -> $dest.bak.$TIMESTAMP"
    fi

    if ln -s "$src" "$dest"; then
        print_success "Linked $dest -> $src"
    else
        print_error "Failed to link $dest -> $src"
        return 1
    fi
}

# git and the compilers all come from the Command Line Tools, so this runs before anything else.
ensure_xcode_clt() {
    [ "$(uname)" = "Darwin" ] || return 0

    if xcode-select -p >/dev/null 2>&1; then
        print_success "Xcode Command Line Tools already installed"
        return 0
    fi

    print_info "Installing Xcode Command Line Tools (a GUI dialog will appear)..."
    xcode-select --install >/dev/null 2>&1

    print_info "Waiting for the Command Line Tools install to finish..."
    local waited=0
    until xcode-select -p >/dev/null 2>&1; do
        sleep 10
        waited=$((waited + 10))
        if [ "$waited" -ge 1800 ]; then
            print_error "Timed out after 30 minutes waiting for Xcode Command Line Tools"
            return 1
        fi
    done

    print_success "Xcode Command Line Tools installed"
}

# Put brew on PATH if it's installed but the shell hasn't been reloaded yet.
load_homebrew_shellenv() {
    command -v brew >/dev/null 2>&1 && return 0
    local candidate
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$candidate" ]; then
            eval "$("$candidate" shellenv)"
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# Bootstrap: when piped from curl there is no repo on disk yet, so clone it
# and re-exec from the clone.
# ---------------------------------------------------------------------------
resolve_scriptpath() {
    local src="${BASH_SOURCE[0]:-$0}"
    [ -f "$src" ] && (cd "$(dirname "$src")" && pwd -P)
}

SCRIPTPATH="$(resolve_scriptpath)"

# .zshrc is the marker for "the whole repo is here", not just this one file.
if [ -z "$SCRIPTPATH" ] || [ ! -f "$SCRIPTPATH/.zshrc" ]; then
    echo -e "${PURPLE}🚀 Bootstrapping dotfiles from $DOTFILES_REPO${NC}"
    ensure_xcode_clt

    if [ -d "$DOTFILES_DIR/.git" ]; then
        print_info "Updating existing clone at $DOTFILES_DIR"
        git -C "$DOTFILES_DIR" pull --ff-only || print_warning "Could not fast-forward $DOTFILES_DIR, using it as-is"
    elif [ -e "$DOTFILES_DIR" ]; then
        echo -e "${RED}❌ $DOTFILES_DIR exists but is not a git clone. Move it aside and re-run.${NC}"
        exit 1
    else
        print_info "Cloning into $DOTFILES_DIR"
        if ! git clone "$DOTFILES_REPO" "$DOTFILES_DIR"; then
            echo -e "${RED}❌ Failed to clone $DOTFILES_REPO${NC}"
            exit 1
        fi
    fi

    # stdin is the curl pipe at this point, which leaves sudo and `gh auth login`
    # with nothing to read from. Reattach the terminal when there is one.
    if [ -e /dev/tty ]; then
        exec bash "$DOTFILES_DIR/setup.sh" "$@" < /dev/tty
    else
        exec bash "$DOTFILES_DIR/setup.sh" "$@"
    fi
fi

echo -e "${PURPLE}🚀 Starting dotfiles setup...${NC}"
echo -e "${CYAN}📁 Script path: $SCRIPTPATH${NC}"
echo ""

if [ "$SCRIPTPATH" != "$HOME/dotfiles" ]; then
    print_warning "Repo lives at $SCRIPTPATH but .zshrc hardcodes \$HOME/dotfiles - the shell config will not load until one of the two is changed"
fi

unamestr=$(uname)

# ---------------------------------------------------------------------------
# Platform packages - everything below depends on these being present
# ---------------------------------------------------------------------------
if [[ "$unamestr" == 'Linux' ]]; then
    echo ""
    print_step "🐧 Detected Linux system - starting Linux-specific setup..."

    print_step "Removing old Vim packages..."
    sudo apt-get remove --yes vim vim-runtime gvim vim-tiny vim-common vim-gui-common vim-nox
    print_success "Old Vim packages removed"

    print_step "Installing apt packages..."
    cat "$SCRIPTPATH/apt-packages.txt" | xargs sudo apt-get --yes --force-yes install
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
    TEMP_PAM=$(mktemp); echo "auth       sufficient   pam_wheel.so trust group=chsh" | cat - /etc/pam.d/chsh > "$TEMP_PAM" && sudo mv "$TEMP_PAM" /etc/pam.d/chsh
    sudo groupadd chsh
    sudo usermod -a -G chsh "$(whoami)"
    chsh -s "$(command -v zsh)"
    print_success "ZSH configured as default shell"

    print_step "Setting up Docker..."
    if sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D; then
        echo "deb https://apt.dockerproject.org/repo ubuntu-trusty main" > /etc/apt/sources.list.d/docker.list
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

    print_step "Checking for Xcode Command Line Tools..."
    ensure_xcode_clt

    print_step "Checking for Homebrew..."
    if load_homebrew_shellenv; then
        print_success "Homebrew already installed ($(command -v brew))"
    else
        print_info "Installing Homebrew..."
        if NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
            if load_homebrew_shellenv; then
                print_success "Homebrew installed ($(command -v brew))"
            else
                print_error "Homebrew installed but brew is not on PATH"
            fi
        else
            print_error "Failed to install Homebrew"
        fi
    fi

    if command -v brew >/dev/null 2>&1; then
        print_step "Installing Homebrew formulae..."
        brew install \
            cmake wget tree fzf forgit \
            git gh vim \
            rbenv ruby-build pyenv jenv nvm \
            python@3 pipx virtualenvwrapper
        if [ $? -eq 0 ]; then
            print_success "Homebrew formulae installed"
        else
            print_error "Failed to install some Homebrew formulae"
        fi

        # The Command Line Tools ship their own git; make sure the Homebrew one wins.
        BREW_GIT="$(brew --prefix)/bin/git"
        if [ ! -x "$BREW_GIT" ]; then
            print_error "Homebrew git not found at $BREW_GIT"
        elif [ "$(command -v git)" = "$BREW_GIT" ]; then
            print_success "git is the Homebrew build ($(git --version))"
        else
            print_warning "git resolves to $(command -v git), not the Homebrew build at $BREW_GIT - check the PATH order in .zshrc"
        fi

        print_step "Installing Homebrew casks..."
        brew install --cask iterm2 visual-studio-code
        if [ $? -eq 0 ]; then
            print_success "Homebrew casks installed"
        else
            print_warning "Failed to install some Homebrew casks (already installed outside brew?)"
        fi
    else
        print_error "Skipping Homebrew packages because brew is unavailable"
    fi

    print_step "Setting up Oh-My-Zsh..."
    if [ -d "$HOME/.oh-my-zsh" ]; then
        print_info "Oh-My-Zsh already installed"
    else
        print_info "Installing Oh-My-Zsh..."
        # KEEP_ZSHRC so the installer leaves our symlinked .zshrc alone
        if RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"; then
            print_success "Oh-My-Zsh installed"
        else
            print_error "Failed to install Oh-My-Zsh"
        fi
    fi

    print_step "Configuring ZSH as default shell..."
    ZSH_PATH="$(command -v zsh)"
    if [ -z "$ZSH_PATH" ]; then
        print_error "zsh not found, cannot set default shell"
    elif [ "$SHELL" = "$ZSH_PATH" ]; then
        print_success "zsh is already the default shell"
    else
        grep -qxF "$ZSH_PATH" /etc/shells || echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
        if chsh -s "$ZSH_PATH"; then
            print_success "ZSH configured as default shell"
        else
            print_warning "Could not change the default shell, run: chsh -s $ZSH_PATH"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Dotfile symlinks
# ---------------------------------------------------------------------------
print_step "Setting up shell profiles..."
link_file "$SCRIPTPATH/.zshrc" "$HOME/.zshrc"
link_file "$SCRIPTPATH/.zshrc" "$HOME/.bash_profile"

print_step "Setting up Vim configuration..."
link_file "$SCRIPTPATH/.vimrc" "$HOME/.vimrc"

print_step "Setting up Git configuration..."
link_file "$SCRIPTPATH/gitfiles/.gitconfig" "$HOME/.gitconfig"
# .gitconfig points core.excludesFile at ~/.gitignore
link_file "$SCRIPTPATH/gitfiles/.gitignore" "$HOME/.gitignore"

print_step "Setting up an SSH key for GitHub..."
SSH_KEY="$HOME/.ssh/id_ed25519"
EXISTING_PUB="$(ls "$HOME"/.ssh/id_*.pub 2>/dev/null | head -1)"
if [ -n "$EXISTING_PUB" ]; then
    print_info "SSH key already present: $EXISTING_PUB"
else
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    if ssh-keygen -t ed25519 -C "$(git config --get user.email 2>/dev/null || whoami)" -f "$SSH_KEY" -N "" >/dev/null; then
        EXISTING_PUB="$SSH_KEY.pub"
        print_success "Generated $SSH_KEY"
    else
        print_error "Failed to generate an SSH key"
    fi
fi

if [[ "$unamestr" == 'Darwin' ]] && [ -n "$EXISTING_PUB" ]; then
    SSH_PRIV="${EXISTING_PUB%.pub}"
    # Keep the key in the agent and the login keychain so it survives reboots
    if ! grep -q '^Host github.com$' "$HOME/.ssh/config" 2>/dev/null; then
        printf '\nHost github.com\n  AddKeysToAgent yes\n  UseKeychain yes\n  IdentityFile %s\n' "$SSH_PRIV" >> "$HOME/.ssh/config"
        chmod 600 "$HOME/.ssh/config"
        print_success "Added a github.com entry to ~/.ssh/config"
    else
        print_info "~/.ssh/config already has a github.com entry"
    fi
    ssh-add --apple-use-keychain "$SSH_PRIV" >/dev/null 2>&1 || ssh-add -K "$SSH_PRIV" >/dev/null 2>&1
fi

# Does SSH actually get us into GitHub? Success exits non-zero, so match the banner.
github_ssh_works() {
    ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 \
        -T git@github.com 2>&1 | grep -q 'successfully authenticated'
}

# Adding a key needs a scope the default login does not request.
upload_ssh_key_to_github() {
    [ -n "$EXISTING_PUB" ] || { print_warning "No SSH public key to upload"; return 1; }
    print_info "Registering $EXISTING_PUB with GitHub..."
    if ! gh auth refresh -h github.com -s admin:public_key; then
        print_error "Could not obtain the admin:public_key scope, run: gh auth refresh -h github.com -s admin:public_key"
        return 1
    fi
    if gh ssh-key add "$EXISTING_PUB" --title "$(scutil --get ComputerName 2>/dev/null || hostname)"; then
        print_success "SSH key added to your GitHub account"
    else
        print_warning "Could not add the SSH key (it may already be registered)"
    fi
}

print_step "Setting up the GitHub CLI..."
if ! command -v gh >/dev/null 2>&1; then
    print_error "gh is not installed, skipping GitHub CLI setup"
else
    if gh auth status >/dev/null 2>&1; then
        print_success "GitHub CLI already authenticated ($(gh api user --jq .login 2>/dev/null || echo 'unknown user'))"
    elif [ -t 0 ]; then
        print_info "Authenticating the GitHub CLI - a browser window will open..."
        if gh auth login --hostname github.com --git-protocol ssh --web; then
            print_success "GitHub CLI authenticated"
        else
            print_error "GitHub CLI authentication failed, run it by hand: gh auth login"
        fi
    else
        print_warning "No terminal attached, GitHub CLI left unauthenticated - run: gh auth login"
    fi

    if gh auth status >/dev/null 2>&1; then
        print_step "Checking SSH access to GitHub..."
        if github_ssh_works; then
            print_success "SSH access to GitHub is working - private clones and pushes will authenticate"
        elif [ -t 0 ]; then
            upload_ssh_key_to_github
            if github_ssh_works; then
                print_success "SSH access to GitHub is working"
            else
                print_error "SSH to GitHub still failing, check: ssh -T git@github.com"
            fi
        else
            print_warning "SSH to GitHub not working and no terminal to fix it - run: gh auth refresh -h github.com -s admin:public_key && gh ssh-key add $EXISTING_PUB"
        fi

        # Wire gh in as the credential helper for HTTPS remotes. This goes in an
        # untracked local config: the global .gitconfig is a symlink into this repo
        # and must not collect machine-specific binary paths.
        print_step "Configuring git credentials for HTTPS remotes..."
        GH_BIN="$(command -v gh)"
        GIT_LOCAL="$HOME/.gitconfig.local"
        git config --file "$GIT_LOCAL" --unset-all credential."https://github.com".helper 2>/dev/null
        git config --file "$GIT_LOCAL" --add credential."https://github.com".helper ""
        if git config --file "$GIT_LOCAL" --add credential."https://github.com".helper "!$GH_BIN auth git-credential"; then
            print_success "gh registered as the HTTPS credential helper in $GIT_LOCAL"
        else
            print_error "Failed to configure the HTTPS credential helper"
        fi
    fi
fi

print_step "Setting up Claude Code skills..."
link_file "$SCRIPTPATH/claude/skills" "$HOME/.claude/skills"

if [[ "$unamestr" == 'Darwin' ]]; then
    print_step "Setting up iTerm2 preferences..."
    # iTerm2 reads its prefs out of a folder we point it at; symlinking into
    # ~/Library/Preferences fights with cfprefsd and loses.
    defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$SCRIPTPATH"
    defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
    if [ $? -eq 0 ]; then
        print_success "iTerm2 pointed at $SCRIPTPATH for preferences"
    else
        print_error "Failed to configure iTerm2 preferences"
    fi

    print_step "Setting up Xcode key bindings..."
    link_file "$SCRIPTPATH/Xcode" "$HOME/Library/Developer/Xcode/UserData/KeyBindings"

    print_step "Setting up VSCode configuration..."
    VSCODE_USER="$HOME/Library/Application Support/Code/User"
    mkdir -p "$VSCODE_USER"
    link_file "$SCRIPTPATH/VSCode/settings.json" "$VSCODE_USER/settings.json"
    link_file "$SCRIPTPATH/VSCode/keybindings.json" "$VSCODE_USER/keybindings.json"
fi

# ---------------------------------------------------------------------------
# Vim plugins
# ---------------------------------------------------------------------------
print_step "Installing Vim Pathogen..."
mkdir -p ~/.vim/autoload ~/.vim/bundle
curl -LSso ~/.vim/autoload/pathogen.vim https://tpo.pe/pathogen.vim
if [ $? -eq 0 ]; then
    print_success "Pathogen installed"
else
    print_error "Failed to install Pathogen"
fi

print_step "Installing Vim plugins..."
cd ~/.vim/bundle || print_error "Could not enter ~/.vim/bundle"
if [ ! -d "./vim-bundler" ]; then
    print_info "Cloning vim-bundler..."
    git clone https://github.com/tpope/vim-bundler.git
    print_success "vim-bundler installed"
else
    print_info "vim-bundler already installed"
fi

if [ ! -d "./Vundle.vim" ]; then
    print_info "Cloning Vundle.vim..."
    git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
    print_success "Vundle.vim installed"
else
    print_info "Vundle.vim already installed"
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
    cd ~/.vim/bundle/YouCompleteMe || true
    ./install.py --clang-completer
    if [ $? -eq 0 ]; then
        print_success "YouCompleteMe built"
    else
        print_error "Failed to build YouCompleteMe"
    fi
else
    print_warning "YouCompleteMe directory not found, skipping build"
fi

# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------
print_step "Installing fzf key bindings and fuzzy completion..."
if command -v brew >/dev/null 2>&1 && [ -x "$(brew --prefix)/opt/fzf/install" ]; then
    yes | "$(brew --prefix)/opt/fzf/install"
    if [ $? -eq 0 ]; then
        print_success "fzf key bindings installed"
    else
        print_error "Failed to install fzf key bindings"
    fi
else
    print_info "fzf not installed via Homebrew, skipping key bindings"
fi

print_step "Installing vimpager..."
if command -v vimpager >/dev/null 2>&1; then
    print_info "vimpager already installed"
else
    VIMPAGER_DIR=$(mktemp -d)
    cd "$VIMPAGER_DIR" || true
    if git clone https://github.com/rkitover/vimpager && cd vimpager && sudo make install; then
        print_success "vimpager installed"
    else
        print_error "Failed to install vimpager"
    fi
fi

print_step "Installing Claude Code..."
if command -v claude >/dev/null 2>&1; then
    print_success "Claude Code already installed ($(command -v claude))"
else
    if curl -fsSL https://claude.ai/install.sh | bash; then
        export PATH="$HOME/.local/bin:$PATH"
        hash -r 2>/dev/null
        print_success "Claude Code installed"
    else
        print_error "Failed to install Claude Code"
    fi
fi

print_step "Signing in to Claude Code..."
if ! command -v claude >/dev/null 2>&1; then
    print_error "claude is not on PATH, skipping sign-in"
elif claude auth status 2>/dev/null | grep -q '"loggedIn"[[:space:]]*:[[:space:]]*true'; then
    print_success "Claude Code already signed in ($(claude auth status 2>/dev/null | sed -n 's/.*"email"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'))"
elif [ -t 0 ]; then
    print_info "Signing in to Claude Code - a browser window will open..."
    if claude auth login; then
        print_success "Claude Code signed in"
    else
        print_error "Claude Code sign-in failed, run it by hand: claude auth login"
    fi
else
    print_warning "No terminal attached, Claude Code left signed out - run: claude auth login"
fi

cd "$SCRIPTPATH" || true

# ---------------------------------------------------------------------------
# Verify the things you actually need working, rather than assuming the
# install steps above were enough.
# ---------------------------------------------------------------------------
echo ""
print_step "Verifying sign-in state..."

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    print_success "gh: signed in as $(gh api user --jq .login 2>/dev/null || echo 'unknown')"
else
    print_error "gh: NOT signed in - run: gh auth login"
fi

if command -v claude >/dev/null 2>&1 && claude auth status 2>/dev/null | grep -q '"loggedIn"[[:space:]]*:[[:space:]]*true'; then
    print_success "claude: signed in as $(claude auth status 2>/dev/null | sed -n 's/.*"email"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
else
    print_error "claude: NOT signed in - run: claude auth login"
fi

if ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 \
       -T git@github.com 2>&1 | grep -q 'successfully authenticated'; then
    print_success "github ssh: working - you can clone and push private repos over SSH"
else
    print_error "github ssh: NOT working - run: ssh -T git@github.com to diagnose"
fi

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
