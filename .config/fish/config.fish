# ============================================================
# ~/.config/fish/config.fish
#
# NixOS manages:
#   - Fish
#   - Starship
#   - zoxide
#   - direnv
#   - fzf.fish
#   - autopair
#
# Keep those integrations OUT of this file.
# This file is for personal shell behavior.
# ============================================================

# ============================================================
# Environment
# ============================================================

set -gx EDITOR nvim
set -gx VISUAL nvim

# User-local executables
fish_add_path -g ~/.local/bin

# Rust/Cargo binaries, if present
fish_add_path -g ~/.cargo/bin

# Doom Emacs command
fish_add_path -g ~/.config/emacs/bin

# Pager
set -gx PAGER less
set -gx LESS '-R -F -X'

# ============================================================
# Interactive shell
# ============================================================

if status is-interactive

    # --------------------------------------------------------
    # Fish
    # --------------------------------------------------------

    # Disable the default "Welcome to fish" message.
    set -g fish_greeting

    # --------------------------------------------------------
    # Navigation
    # --------------------------------------------------------

    abbr --add .. 'cd ..'
    abbr --add ... 'cd ../..'
    abbr --add .... 'cd ../../..'

    abbr --add c clear

    # --------------------------------------------------------
    # Git
    # --------------------------------------------------------

    abbr --add g git

    abbr --add gs 'git status -sb'

    abbr --add ga 'git add'
    abbr --add gaa 'git add --all'

    abbr --add gc 'git commit'
    abbr --add gcm 'git commit -m'
    abbr --add gca 'git commit --amend'

    abbr --add gd 'git diff'
    abbr --add gds 'git diff --staged'

    abbr --add gl 'git log --oneline --decorate --graph'

    abbr --add gp 'git push'
    abbr --add gpl 'git pull'
    abbr --add gpf 'git push --force-with-lease'

    abbr --add gf 'git fetch --all --prune'

    abbr --add gb 'git branch'
    abbr --add gba 'git branch --all'

    abbr --add gsw 'git switch'
    abbr --add gsc 'git switch -c'

    abbr --add grb 'git rebase'
    abbr --add grbi 'git rebase -i'

    # dot: git for the config repo in ~/.dotfiles, whose files stay where they are in the home folder.
    abbr --add dot 'git --git-dir=$HOME/.dotfiles --work-tree=$HOME'
    abbr --add dotg 'lazygit --git-dir=$HOME/.dotfiles --work-tree=$HOME'

    # --------------------------------------------------------
    # NixOS
    # --------------------------------------------------------

    # Build the configuration in ~/nixos (/etc/nixos is a link to it) and switch
    # to it.
    abbr --add nrs 'sudo nixos-rebuild switch'
    abbr --add nrb 'sudo nixos-rebuild boot'
    abbr --add nrsu 'sudo nixos-rebuild switch --upgrade'

    # Build it without applying it.
    abbr --add ncheck "nix-build '<nixpkgs/nixos>' -A system --no-out-link"

    # Move the nixos channel to its newest revision; nrs then applies it.
    abbr --add nup 'sudo nix-channel --update'

    # Cleanup. ngc removes all old generations (no rollback); ngc7 keeps a week.
    abbr --add ngc 'sudo nix-collect-garbage -d'
    abbr --add ngc7 'sudo nix-collect-garbage --delete-older-than 7d'
    abbr --add nopt 'nix-store --optimise'

    # --------------------------------------------------------
    # eza
    # --------------------------------------------------------

    if command -q eza
        abbr --add l 'eza --group-directories-first'
        abbr --add ll 'eza -lah --group-directories-first'
        abbr --add la 'eza -a --group-directories-first'
        abbr --add lt 'eza -lah --tree --level=2 --group-directories-first'
    end

    # --------------------------------------------------------
    # bat
    # --------------------------------------------------------

    # Keep the normal `cat` command untouched.
    # Use `bat` explicitly when you want syntax highlighting.

    # --------------------------------------------------------
    # Useful Fish functions
    # --------------------------------------------------------

    # Create a directory and enter it.
    function mkcd
        if test (count $argv) -ne 1
            echo "usage: mkcd DIRECTORY"
            return 2
        end

        mkdir -p -- $argv[1]
        and cd -- $argv[1]
    end

    # Go up N directories.
    # Example:
    #   up
    #   up 3
    function up
        set -l levels 1

        if test (count $argv) -gt 0
            set levels $argv[1]
        end

        if not string match -rq '^[0-9]+$' -- $levels
            echo "usage: up [levels]"
            return 2
        end

        for i in (seq $levels)
            cd ..
            or return
        end
    end

    # Jump to the root of the current Git repository.
    function croot
        set -l root (git rev-parse --show-toplevel 2>/dev/null)

        if test $status -ne 0
            echo "Not inside a Git repository."
            return 1
        end

        cd $root
    end

    # Show listening/network sockets.
    function ports
        if command -q ss
            ss -tulpn
        else if command -q lsof
            lsof -i -P -n
        else
            echo "Neither ss nor lsof is installed."
            return 1
        end
    end

    # Extract common archive formats.
    function extract
        if test (count $argv) -ne 1
            echo "usage: extract FILE"
            return 2
        end

        set -l file $argv[1]

        if not test -f $file
            echo "File not found: $file"
            return 1
        end

        switch $file
            case '*.tar.bz2'
                tar xjf $file
            case '*.tar.gz'
                tar xzf $file
            case '*.tar.xz'
                tar xJf $file
            case '*.tar.zst'
                tar --use-compress-program=unzstd -xf $file
            case '*.tar'
                tar xf $file
            case '*.bz2'
                bunzip2 $file
            case '*.gz'
                gunzip $file
            case '*.xz'
                unxz $file
            case '*.zip'
                unzip $file
            case '*.7z'
                7z x $file
            case '*'
                echo "Unsupported archive format: $file"
                return 1
        end
    end

    # --------------------------------------------------------
    # Quality-of-life aliases/abbreviations
    # --------------------------------------------------------

    # Docker
    if command -q docker
        abbr --add d docker
        abbr --add dc 'docker compose'
        abbr --add dps 'docker ps'
        abbr --add dpsa 'docker ps -a'
        abbr --add di 'docker images'
    end

    # Kubernetes
    if command -q kubectl
        abbr --add k kubectl
        abbr --add kgp 'kubectl get pods'
        abbr --add kgs 'kubectl get svc'
        abbr --add kgn 'kubectl get nodes'
    end

    # --------------------------------------------------------
    # System shortcuts
    # --------------------------------------------------------

    if command -q systemctl
        abbr --add sc systemctl
        abbr --add scu 'systemctl --user'
    end

    # --------------------------------------------------------
    # Zed
    # --------------------------------------------------------

    abbr --add zed zeditor

    # --------------------------------------------------------
    # Search helpers
    # --------------------------------------------------------

    # fzf.fish is managed by NixOS.
    #
    # Keep these tools untouched so fzf.fish can provide its
    # own Ctrl-R / file / directory / process integrations.
    #
    # Useful tools available from your NixOS configuration:
    #
    #   fzf
    #   fd
    #   bat
    #   eza
    #
    # Do not manually rebind fzf.fish here unless needed.

    # --------------------------------------------------------
    # Prompt
    # --------------------------------------------------------

    # Starship is initialized by NixOS.
    #
    # DO NOT add:
    #
    #   starship init fish | source
    #
    # to this file.

    # --------------------------------------------------------
    # Shell startup message
    # --------------------------------------------------------

    # Optional: show a small system message only when desired.
    #
    # function fish_user_key_bindings
    #     ...
    # end

end
