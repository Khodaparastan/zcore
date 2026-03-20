#!/usr/bin/env zsh
#
# Alias Definition Module
# Defines a set of general, tool-specific, and platform-specific aliases.
#

# ==============================================================================
# MAIN INITIALIZATION
# ==============================================================================
__z::mod::aliases::init() {
  emulate -L zsh
  z::log::info "Defining aliases..."
  z::env::alias_set pass "gopass"
  # --- Network ---
  z::env::alias_set myip 'curl -s https://api.ipify.org; echo'
  # --- Editor ---
  z::env::alias_set v '${VISUAL:-${EDITOR:-vi}}'
  z::env::alias_set E 'sudo -E ${VISUAL:-${EDITOR:-vi}}'

  # --- Navigation ---
  z::env::alias_set up 'cd ..'
  z::env::alias_set up2 'cd ../../'
  z::env::alias_set cd- 'cd -'
  z::env::alias_set home 'cd ~'
  z::env::alias_set dev 'cd ~/dev'
  z::env::alias_set zss 'cd ~/.ssh'
  z::env::alias_set zdd 'cd "${XDG_CONFIG_HOME:-$HOME/.config}"'

  # --- System & File Operations ---
  z::env::alias_set df 'df -h'
  z::probe::cmd "free" &&
    z::env::alias_set free 'free -h'
  z::env::alias_set mkdir 'mkdir -pv'
  z::env::alias_set ping 'ping -c 5'
  # if ((IS_MACOS)); then
  #   z::env::alias_set cp 'cp -iv'
  #   z::env::alias_set mv 'mv -iv'
  #   z::env::alias_set rm 'rm -iv'
  # else
  #   z::env::alias_set cp 'cp -iv --preserve=all'
  #   z::env::alias_set mv 'mv -iv'
  #   z::env::alias_set rm 'rm -Iv --preserve-root'
  # fi

  # --- Enhanced Tool Replacements ---
  z::probe::cmd "yazi" && z::env::alias_set y 'yazi'
  z::probe::cmd "nvim" && z::env::alias_set v 'nvim' && z::env::alias_set vim 'nvim'
  # z::probe::cmd "bat" &&
  #   z::env::alias_set cat 'bat --style=plain --paging=never'
  # z::probe::cmd "rg" &&
  #   z::env::alias_set grep 'rg --color=always --smart-case'
  # z::probe::cmd "fd" &&
  #   z::env::alias_set find 'fd --hidden --follow --exclude .git'
  z::probe::cmd "btop" &&
    z::env::alias_set top 'btop' ||
    z::probe::cmd "htop" &&
    z::env::alias_set top 'htop'
  # z::probe::cmd "delta" &&
  #   z::env::alias_set diff 'delta'

  # --- Git ---
  if z::probe::cmd "git"; then
    z::env::alias_set g 'git'
    z::env::alias_set ga 'git add'
    z::env::alias_set gaa 'git add --all'
    z::env::alias_set gs 'git status -sb'
    z::env::alias_set gss 'git status'
    z::env::alias_set gc 'git commit -v'
    z::env::alias_set gca 'git commit -v --amend'
    z::env::alias_set gco 'git checkout'
    z::env::alias_set gcb 'git checkout -b'
    z::env::alias_set gp 'git push'
    z::env::alias_set gpf 'git push --force-with-lease'
    z::env::alias_set gpl 'git pull --rebase --autostash'
    z::env::alias_set gl "git log --oneline --graph --decorate --all -20"
    z::env::alias_set glog "git log --graph --pretty=format:'%Cred%h%Creset %s %Cgreen(%cr)'"
    z::env::alias_set gd 'git diff'
    z::env::alias_set gds 'git diff --staged'
  fi

  # --- SSH ---
  z::env::alias_set skr 'ssh-keygen -R'
  z::env::alias_set sci 'ssh-copy-id -i'
  z::env::alias_set ssi 'ssh -i'

  # --- Platform Specific ---
  if ((IS_MACOS)); then
    z::env::alias_set o 'open'
    z::env::alias_set clip 'pbcopy'
    z::env::alias_set flushdns 'sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder'
    z::env::alias_set brewup 'brew update && brew upgrade && brew autoremove && brew cleanup --prune=all'
  elif ((IS_LINUX)); then
    z::env::alias_set o 'xdg-open'
    if z::probe::cmd "xclip"; then
      z::env::alias_set clip 'xclip -selection clipboard'
    elif z::probe::cmd "wl-copy"; then
      z::env::alias_set clip 'wl-copy'
    fi
    if z::probe::cmd "apt"; then
      z::env::alias_set aptup 'sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y'
    elif z::probe::cmd "dnf"; then
      z::env::alias_set dnfup 'sudo dnf upgrade -y && sudo dnf autoremove -y'
    elif z::probe::cmd "pacman"; then
      z::env::alias_set pacup 'sudo pacman -Syu --noconfirm'
    fi
  fi

  z::env::alias_set dl 'aria2c -x6'
  z::log::info "Aliases defined successfully."
}

if z::probe::func "__z::mod::aliases::init"; then
  __z::mod::aliases::init
fi
