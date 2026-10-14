# NixPad: NixOS and desktop config

This repo holds everything needed to rebuild this laptop's system and desktop:
the NixOS config in `nixos/` (apps, services, boot, theme) and the desktop configs
in `.config/` (mango, the Quickshell bar, lock screen, kitty, colours, yazi,
editors, and the wallpaper in use). No personal data is in it.

It is a **bare git repo**: the history lives in `~/.dotfiles`, and the files stay
where they belong in the home folder. The `dot` command (a fish abbreviation) is
`git` for this repo.

## Everyday use

| Command | What it does |
|---|---|
| `dot status` | what changed since the last save |
| `dot diff` | the changed lines |
| `dot add -u` | stage every change to files already in the repo |
| `dot commit -m "what changed"` | save the staged changes |
| `dot add PATH` | start tracking a new file |
| `dot add -u && dot add -A ~/.config/mango` | after a wallpaper change: stage the new picture and the colours made from it |
| `dot log --oneline` | the list of saves |
| `dotg` | the same repo in lazygit (it needs both folders named, which `dotg` does) |

> **The working folder of this repo is the whole home folder.** `~/.gitignore`
> ignores everything except the configs kept here, so "stage all" (`dot add -A`,
> or `a` in lazygit) cannot pick up SSH keys, browser profiles or other private
> files. To track a *new* app's config, first add a `!` line for it to
> `~/.gitignore` (for example `!/.config/newapp/`), then `dot add` it.

## What is not in here

Browser profiles, 1Password, SSH keys, Syncthing and RustDesk identities,
Obsidian, Spotify, the other wallpapers in `~/Pictures/Backgrounds`, and all
personal folders. Wi-Fi passwords, Bluetooth pairings, fingerprints and the
Tailscale login live outside the home folder. Back these up separately, or set
them up again (see "After the first login").

## Keep a copy off the laptop

A copy only on this laptop is lost with the laptop.

- USB drive: `git clone --bare ~/.dotfiles /run/media/kishan/<drive>/dotfiles.git`
  (update it later with `dot push /run/media/kishan/<drive>/dotfiles.git main`)
- GitHub (private repo): `dot remote add origin git@github.com:<user>/<repo>.git`, then `dot push -u origin main`

## Fresh install

**Before wiping:** push or copy the newest state, check the channel with
`sudo nix-channel --list` (it should be nixos-unstable), and have the
1Password Emergency Kit (Secret Key) at hand.

1. Install NixOS from the USB installer with the user name **`kishan`**
   (paths such as `/home/kishan` are written into the config). Log in.
2. Get git for this shell:
   `nix-shell -p git`
3. Clone the repo and make the `dot` command for this shell:
   ```sh
   git clone --bare <USB path or GitHub URL> ~/.dotfiles
   alias dot='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'
   dot config status.showUntrackedFiles no
   ```
4. Put the files in place:
   `dot checkout`
   If it refuses because a file already exists, move that file away and run it again.
5. Keep the new machine's disk file, then point the system at `~/nixos`:
   ```sh
   cp /etc/nixos/hardware-configuration.nix ~/nixos/
   sudo mv /etc/nixos /etc/nixos.installer
   sudo ln -s /home/kishan/nixos /etc/nixos
   ```
6. Add the channel:
   `sudo nix-channel --add https://nixos.org/channels/nixos-unstable nixos && sudo nix-channel --update`
7. Build and switch, then reboot:
   `sudo nixos-rebuild switch && reboot`
8. Save the new disk file:
   `dot add -u && dot commit -m "New hardware configuration"`

## After the first login

| What | How |
|---|---|
| Wi-Fi | click NET in the bar, pick the network, type the password |
| Bluetooth | click BT in the bar and pair each device |
| Fingerprints | Super+D, section FINGERPRINT, click an empty box (or `fprintd-enroll`) |
| Tailscale | `sudo tailscale up`, log in in the browser, then set the machine's `100.80.80.x` address in the admin console; starting and stopping without sudo is set by the config |
| 1Password | sign in with the Secret Key |
| Zen | start it once, then copy `~/.config/zen/6qz5anbx.kishan/user.js` into the new profile folder (its name is in `~/.config/zen/profiles.ini`); sign in and add extensions |
| Helium | sign in and add extensions |
| Syncthing | open http://127.0.0.1:8384, add the other devices and the Obsidian Vault folder again (the laptop gets a new device ID) |
| RustDesk | gets a new ID |
| Doom Emacs | `git clone --depth 1 https://github.com/doomemacs/core ~/.config/emacs && ~/.config/emacs/bin/doom install` |
| Neovim | plugins install by themselves on the first start |
| SSH | restore `~/.ssh` from a backup, or make a new key |
| Wallpapers | only the one in use is here; copy `~/Pictures/Backgrounds` back for the rest |

## Handy commands

| Command | What it does |
|---|---|
| `nrs` | apply the NixOS config (`sudo nixos-rebuild switch`) |
| `ncheck` | build it without applying |
| `nup` | move the channel to its newest version (then `nrs`) |
| `sysupdate` | channel, browsers, switch and clean-up in one go |
| `sysclean` | show what can be cleaned; `sysclean go` cleans |
| Super+Shift+R | reload the bar |
| Super+W | pick a wallpaper |
