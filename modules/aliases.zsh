#!/usr/bin/env zsh
#
# Alias Definition Module
# Defines a set of general, tool-specific, and platform-specific aliases.
#

# ==============================================================================
# MAIN INITIALIZATION
# ==============================================================================
z::mod::aliases::init() {
  emulate -L zsh
  z::runtime::check_interrupted ||
    return $?
  z::log::info "Defining aliases..."

  # --- Editor ---
  z::alias::define v '${VISUAL:-${EDITOR:-vi}}'
  z::alias::define E 'sudo -E ${VISUAL:-${EDITOR:-vi}}'

  # --- Navigation ---
  z::alias::define up 'cd ..'
  z::alias::define up2 'cd ../../'
  z::alias::define cd- 'cd -'
  z::alias::define home 'cd ~'
  z::alias::define dev 'cd ~/dev'
  z::alias::define zss 'cd ~/.ssh'
  z::alias::define zdd 'cd "${XDG_CONFIG_HOME:-$HOME/.config}"'

  # --- System & File Operations ---
  z::alias::define df 'df -h'
  z::cmd::exists "free" &&
    z::alias::define free 'free -h'
  z::alias::define mkdir 'mkdir -pv'
  z::alias::define ping 'ping -c 5'
  if ((IS_MACOS)); then
    z::alias::define cp 'cp -iv'
    z::alias::define mv 'mv -iv'
    z::alias::define rm 'rm -iv'
  else
    z::alias::define cp 'cp -iv --preserve=all'
    z::alias::define mv 'mv -iv'
    z::alias::define rm 'rm -Iv --preserve-root'
  fi

  # --- Enhanced Tool Replacements ---
  z::cmd::exists "yazi" && z::alias::define y 'yazi'
  z::cmd::exists "nvim" && z::alias::define v 'nvim' && z::alias::define vim 'nvim'
  z::cmd::exists "bat" &&
    z::alias::define cat 'bat --style=plain --paging=never'
  z::cmd::exists "rg" &&
    z::alias::define grep 'rg --color=always --smart-case'
  z::cmd::exists "fd" &&
    z::alias::define find 'fd --hidden --follow --exclude .git'
  z::cmd::exists "btop" &&
    z::alias::define top 'btop' ||
    z::cmd::exists "htop" &&
    z::alias::define top 'htop'
  z::cmd::exists "delta" &&
    z::alias::define diff 'delta'

  # --- Git ---
  if z::cmd::exists "git"; then
    z::alias::define g 'git'
    z::alias::define ga 'git add'
    z::alias::define gaa 'git add --all'
    z::alias::define gs 'git status -sb'
    z::alias::define gss 'git status'
    z::alias::define gc 'git commit -v'
    z::alias::define gca 'git commit -v --amend'
    z::alias::define gco 'git checkout'
    z::alias::define gcb 'git checkout -b'
    z::alias::define gp 'git push'
    z::alias::define gpf 'git push --force-with-lease'
    z::alias::define gpl 'git pull --rebase --autostash'
    z::alias::define gl "git log --oneline --graph --decorate --all -20"
    z::alias::define glog "git log --graph --pretty=format:'%Cred%h%Creset %s %Cgreen(%cr)'"
    z::alias::define gd 'git diff'
    z::alias::define gds 'git diff --staged'
  fi

  # --- SSH ---
  z::alias::define skr 'ssh-keygen -R'
  z::alias::define sci 'ssh-copy-id -i'
  z::alias::define ssi 'ssh -i'

  # --- Platform Specific ---
  if ((IS_MACOS)); then
    z::alias::define o 'open'
    z::alias::define clip 'pbcopy'
    z::alias::define flushdns 'sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder'
    z::alias::define brewup 'brew update && brew upgrade && brew autoremove && brew cleanup --prune=all'
  elif ((IS_LINUX)); then
    z::alias::define o 'xdg-open'
    if z::cmd::exists "xclip"; then
      z::alias::define clip 'xclip -selection clipboard'
    elif z::cmd::exists "wl-copy"; then
      z::alias::define clip 'wl-copy'
    fi
    if z::cmd::exists "apt"; then
      z::alias::define aptup 'sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y'
    elif z::cmd::exists "dnf"; then
      z::alias::define dnfup 'sudo dnf upgrade -y && sudo dnf autoremove -y'
    elif z::cmd::exists "pacman"; then
      z::alias::define pacup 'sudo pacman -Syu --noconfirm'
    fi
  fi

  z::log::info "Aliases defined successfully."
}

if z::func::exists "z::mod::aliases::init"; then
  z::mod::aliases::init
fi
