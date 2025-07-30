_define_aliases() {
  _setup_editor_aliases() {
    alias v='command ${VISUAL:-${EDITOR:-vi}}'
    alias vi='command ${VISUAL:-${EDITOR:-vi}}'
    alias vim='command ${VISUAL:-${EDITOR:-vi}}'
    alias nvi='command ${VISUAL:-${EDITOR:-vi}}'
    alias E="sudo -E command ${VISUAL:-${EDITOR:-vi}}"
  }

  _setup_system_aliases() {
    alias df='df -h'
    alias free='free -h'
    alias ping='ping -c 5'
    alias mkdir='mkdir -pv'
    alias which='command -v'

    if ((IS_MACOS)); then
      alias du='du -sh'
      alias cp='cp -iv'
      alias mv='mv -iv'
    else
      alias du='du -sh'
      alias rm='rm -Iv --preserve-root'
      alias cp='cp -iv --preserve=all'
      alias mv='mv -iv'
      alias ps='ps auxf'

    fi
  }

  _setup_enhanced_tools() {
    if command -v bat >/dev/null 2>&1; then
      alias cat='bat --style=plain --paging=never'
      alias ccat='bat --style=plain --paging=never'
      alias batp='bat --style=numbers --color=always'
    fi
    if command -v rg >/dev/null 2>&1; then
      alias grep='rg --color=always --smart-case'
      alias rgrep='rg'
    fi
    if command -v fd >/dev/null 2>&1; then
      alias find='fd --hidden --follow --exclude .git'
      alias ffind='fd'
    fi
    if command -v btop >/dev/null 2>&1; then
      alias top='btop'
    elif command -v htop >/dev/null 2>&1; then alias top='htop'; fi
    if command -v delta >/dev/null 2>&1; then
      alias diff='delta'
    elif command -v colordiff >/dev/null 2>&1; then alias diff='colordiff'; fi
  }

  _setup_git_aliases() {
    if ! command -v git >/dev/null 2>&1; then return 0; fi
    alias g='git'
    alias ga='git add'
    alias gaa='git add --all'
    alias gap='git add --patch'
    alias gs='git status -sb'
    alias gss='git status'
    alias gc='git commit -v'
    alias gca='git commit -v --amend'
    alias gcane='git commit -v --amend --no-edit'
    alias gco='git checkout'
    alias gcb='git checkout -b'
    alias gcm='git checkout $(git symbolic-ref refs/remotes/origin/HEAD | sed "s@^refs/remotes/origin/@@")'
    alias gcd='git checkout develop'
    alias gp='git push'
    alias gpf='git push --force-with-lease'
    alias gpu='git push -u origin HEAD'
    alias gpl='git pull --rebase --autostash'
    alias gpr='git pull --rebase'
    alias gf='git fetch --all --prune --tags'
    alias gr='git rebase'
    alias gra='git rebase --abort'
    alias grc='git rebase --continue'
    alias grs='git rebase --skip'
    alias gm='git merge'
    alias gma='git merge --abort'
    alias gmc='git merge --continue'
    alias gl="git log --oneline --graph --decorate --all -20"
    alias glog="git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
    alias gll='git log --stat --max-count=5'
    alias gd='git diff'
    alias gds='git diff --staged'
    alias gsh='git show'
    alias gb='git branch'
    alias gba='git branch -a'
    alias gbd='git branch -d'
    alias gbD='git branch -D'
    alias gbr='git branch -r'
    alias gbm='git branch --merged | grep -vE "^\\*?\\s*(master|main|develop)$" | xargs -n 1 git branch -d'
    alias gst='git stash'
    alias gstp='git stash pop'
    alias gstd='git stash drop'
    alias gsts='git stash show -p'
    alias gsl='git stash list'
    alias gcl='git clean -fd'
    alias gca!='git commit -v --amend --no-edit && git push --force-with-lease'
    alias greset='git reset HEAD~'
  }

  _setup_utility_aliases() {
    alias ..='cd ..'
    alias ...='cd ../..'
    alias ....='cd ../../..'
    alias .....='cd ../../../..'
    alias -- -='cd -'
    alias ~='cd ~'

    alias c='clear'
    alias h='history 1'
    alias hg='history 1 | grep'
    alias q='exit'
    alias job='jobs -l'

    if ((!IS_MACOS)); then
      alias chown='chown --preserve-root'
      alias chmod='chmod --preserve-root'
      alias chgrp='chgrp --preserve-root'
    fi

    if command -v curl >/dev/null 2>&1; then
      alias myip='curl -s4 ifconfig.me/ip || curl -s4 ipinfo.io/ip || echo "IP lookup failed"'
    fi

    if command -v tar >/dev/null 2>&1; then
      alias tarx='tar -xzvf'
      alias tarc='tar -czvf'
      # alias tart='tar -tzvf'
      alias tarjx='tar -xjvf'
      alias tarjc='tar -cjvf'
      alias tarjt='tar -tjvf'
    fi

    alias psg='ps aux | grep -v grep | grep -iE --color=auto'
    if command -v ss >/dev/null 2>&1; then
      alias ports='ss -tulnp'
    elif command -v netstat >/dev/null 2>&1; then
      alias ports='netstat -tulnp'
    fi

    alias md='mkdir -p'
    alias rd='rmdir'
  }

  _setup_platform_aliases() {
    if ((IS_MACOS)); then
      alias flushdns='sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder'
      alias showfiles='defaults write com.apple.finder AppleShowAllFiles YES && killall Finder'
      alias hidefiles='defaults write com.apple.finder AppleShowAllFiles NO && killall Finder'
      alias cleanupds='find . -type f -name ".DS_Store" -ls -delete'
      alias brewup='brew update && brew upgrade && brew outdated && brew autoremove && brew cleanup --prune=all && brew doctor && brew bundle dump --force && echo "Brew update complete. Consider committing Brewfile changes."'
      alias lock='pmset displaysleepnow'

      alias desktop='cd ~/Desktop'
      alias downloads='cd ~/Downloads'
      alias documents='cd ~/Documents'

      alias cpu='sysctl -n machdep.cpu.brand_string'
    elif ((IS_LINUX)); then
      alias open='xdg-open'
      if command -v xclip >/dev/null 2>&1; then
        alias pbcopy='xclip -selection clipboard'
        alias pbpaste='xclip -selection clipboard -o'
      elif command -v wl-copy >/dev/null 2>&1 && command -v wl-paste >/dev/null 2>&1; then
        alias pbcopy='wl-copy'
        alias pbpaste='wl-paste'
      fi
      if command -v locate >/dev/null 2>&1; then alias updatedb='sudo updatedb'; fi

      if command -v apt >/dev/null 2>&1; then
        alias aptup='sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y && sudo apt clean'
        alias apti='sudo apt install'
        alias apts='apt search'
        alias aptrm='sudo apt remove'
      elif command -v dnf >/dev/null 2>&1; then
        alias dnfup='sudo dnf upgrade -y && sudo dnf autoremove -y && sudo dnf clean all'
        alias dnfi='sudo dnf install'
        alias dnfs='dnf search'
        alias dnfrm='sudo dnf remove'
      elif command -v pacman >/dev/null 2>&1; then
        alias pacup='sudo pacman -Syu --noconfirm'
        alias paci='sudo pacman -S --noconfirm'
        alias pacs='pacman -Ss'
        alias pacrm='sudo pacman -Rns --noconfirm'
      fi
      alias distro='cat /etc/*release | grep PRETTY_NAME | cut -d "=" -f 2- | tr -d "\"" || lsb_release -ds 2>/dev/null || echo "N/A"'
      alias kernel='uname -r'
    fi
  }

  _setup_editor_aliases
  _setup_system_aliases
  _setup_enhanced_tools
  _setup_git_aliases
  _setup_utility_aliases
  _setup_platform_aliases
}
