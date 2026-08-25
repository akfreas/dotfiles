# dotfiles

Alex Freas' personal dotfiles: zsh, vim, git, iTerm2, Xcode, VS Code, and Claude Code configuration, plus a `setup.sh` that takes a machine from fresh-out-of-the-box to fully configured.

macOS is the primary target. There is a Linux (Debian/Ubuntu) path in `setup.sh`, but it is old and much less exercised.

## Install

On a brand new machine, with nothing installed:

```bash
curl -fsSL https://raw.githubusercontent.com/akfreas/dotfiles/master/setup.sh | bash
```

That is all that's needed. The script bootstraps itself: it installs the Xcode Command Line Tools (which is where `git` comes from), clones this repo to `~/dotfiles`, and re-runs itself from the clone.

If the repo is already cloned, run it directly:

```bash
cd ~/dotfiles && ./setup.sh
```

Both forms are idempotent — re-run the script any time to pick up changes or repair a partial run.

### Options

| Variable | Default | Purpose |
| --- | --- | --- |
| `DOTFILES_DIR` | `~/dotfiles` | Where the repo gets cloned |
| `DOTFILES_REPO` | `https://github.com/akfreas/dotfiles.git` | Where to clone from |

`.zshrc` hardcodes `$HOME/dotfiles` as the config root, so changing `DOTFILES_DIR` also means editing `.zshrc`. The script warns when the two disagree.

## What it does

**Toolchain**

- Xcode Command Line Tools, then Homebrew (waits for the CLT GUI installer to actually finish before continuing)
- Homebrew formulae: `cmake`, `wget`, `tree`, `fzf`, `forgit`, `git`, `gh`, `vim`, `rbenv`, `ruby-build`, `pyenv`, `jenv`, `nvm`, `python@3`, `pipx`, `virtualenvwrapper`
- Homebrew casks: `iterm2`, `visual-studio-code`
- Oh My Zsh, installed unattended so it doesn't clobber the symlinked `.zshrc`
- zsh set as the login shell
- Claude Code, via the official native installer, then signed in with `claude auth login`
- GitHub CLI, signed in with `gh auth login --git-protocol ssh --web`
- An `ed25519` SSH key, generated if you don't already have one, added to the agent and the login keychain, and uploaded to your GitHub account

`git` comes from Homebrew rather than the Command Line Tools; the script verifies that `git` on `PATH` actually resolves to the Homebrew build and warns if something is shadowing it.

### Sign-in

The script logs you in rather than just installing the binaries. It ends with a verification block that checks all three and reports each one explicitly:

```
🔵 Verifying sign-in state...
✅ gh: signed in as akfreas
✅ claude: signed in as alex@freas.me
✅ github ssh: working - you can clone and push private repos over SSH
```

Anything not working is reported as an error with the command to fix it, and the script exits non-zero.

Uploading an SSH key needs the `admin:public_key` scope, which a default `gh auth login` does not request, so the script runs `gh auth refresh` for it — but only if SSH to GitHub isn't already working.

For HTTPS remotes, `gh` is registered as the git credential helper. That gets written to `~/.gitconfig.local`, not the global config, because `~/.gitconfig` is a symlink into this repo and must not collect machine-specific binary paths. The tracked `.gitconfig` pulls it in with an `[include]`.

All of these are interactive, so they only run when a terminal is attached. Under `curl | bash` the script reattaches `/dev/tty` when there is one, so the piped install can still prompt (this is also what makes `sudo` work). With no terminal at all it skips the logins and tells you which commands to run yourself.

**Symlinks** (anything already in place is backed up to `<name>.bak.<timestamp>` first)

| Link | Target |
| --- | --- |
| `~/.zshrc`, `~/.bash_profile` | `.zshrc` |
| `~/.vimrc` | `.vimrc` |
| `~/.gitconfig` | `gitfiles/.gitconfig` |
| `~/.gitignore` | `gitfiles/.gitignore` (the global excludes file `.gitconfig` points at) |
| `~/.claude/skills` | `claude/skills` |
| `~/Library/Developer/Xcode/UserData/KeyBindings` | `Xcode/` |
| `~/Library/Application Support/Code/User/{settings,keybindings}.json` | `VSCode/` |

**iTerm2** is configured by pointing it at this repo as its preferences folder (`PrefsCustomFolder`), which is iTerm2's own supported mechanism. Symlinking the plist into `~/Library/Preferences` does not survive `cfprefsd`.

**Vim** gets Pathogen, Vundle, every plugin in `.vimrc` via `:BundleInstall`, a compiled YouCompleteMe, and `vimpager`.

## After the script

- Open a new terminal, or `source ~/.zshrc`
- iTerm2 must be restarted to read the preferences folder
- Xcode itself comes from the App Store; install it before the key bindings in `Xcode/` are of any use
- `nvm`, `pyenv`, `rbenv`, and `jenv` are installed but have no runtimes yet — install the versions you need
- Anything the script could not do is printed in a summary at the end, and the script exits non-zero

## Layout

```
.zshrc                 shell config, sources everything below
.general.profile       aliases and general shell setup
.sashimiblade.profile  host-specific bits
variables.sh           exported environment variables
functions.sh           shell functions (ramdisk helpers, etc.)
.colors                terminal color definitions
.vimrc                 vim config (Vundle plugin list)
gitfiles/              .gitconfig and global .gitignore
claude/skills/         Claude Code skills, linked to ~/.claude/skills
VSCode/                settings.json and keybindings.json
Xcode/                 key bindings, color theme, breakpoints
iTerm2/                exported profiles
com.googlecode.iterm2.plist   iTerm2 preferences (read in place)
apt-packages.txt       package list for the Linux path
setup.sh               this whole thing
```

## Notes

The script never stops on the first failure. It collects errors as it goes and prints a summary at the end, so one broken step doesn't block the rest of the setup.

A few steps need `sudo` — adding zsh to `/etc/shells` and installing `vimpager` — so it will prompt.
