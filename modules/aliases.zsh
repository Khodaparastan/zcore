_define_aliases() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset warn_create_global

	z::runtime::check_interrupted || return $?

	# Editor aliases (respect VISUAL/EDITOR at invocation time)
	z::alias::define v   "command \${VISUAL:-\${EDITOR:-vi}}"
	z::alias::define vi  "command \${VISUAL:-\${EDITOR:-vi}}"
	z::alias::define vim "command \${VISUAL:-\${EDITOR:-vi}}"
	z::alias::define nvi "command \${VISUAL:-\${EDITOR:-vi}}"
	z::alias::define E   "sudo -E command \${VISUAL:-\${EDITOR:-vi}}"

	# System aliases (portable where possible)
	z::alias::define df 'df -h'
	if command -v free >/dev/null 2>&1; then
		z::alias::define free 'free -h'
	fi
	z::alias::define ping 'ping -c 5'
	z::alias::define mkdir 'mkdir -pv'
	z::alias::define which 'command -v'

	if (( IS_MACOS )); then
		z::alias::define cp 'cp -iv'
		z::alias::define mv 'mv -iv'
	else
		z::alias::define rm 'rm -Iv --preserve-root'
		z::alias::define cp 'cp -iv --preserve=all'
		z::alias::define mv 'mv -iv'
		z::alias::define ps 'ps auxf'
	fi
	z::alias::define du 'du -sh'

	# Enhanced tool replacements (only if tools exist)
	if command -v bat >/dev/null 2>&1; then
		z::alias::define cat  'bat --style=plain --paging=never'
		z::alias::define ccat 'bat --style=plain --paging=never'
		z::alias::define batp 'bat --style=numbers --color=always'
	fi
	if command -v rg >/dev/null 2>&1; then
		z::alias::define grep  'rg --color=always --smart-case'
		z::alias::define rgrep 'rg'
	fi
	if command -v fd >/dev/null 2>&1; then
		z::alias::define find  'fd --hidden --follow --exclude .git'
		z::alias::define ffind 'fd'
	fi
	if command -v btop >/dev/null 2>&1; then
		z::alias::define top 'btop'
	elif command -v htop >/dev/null 2>&1; then
		z::alias::define top 'htop'
	fi
	if command -v delta >/dev/null 2>&1; then
		z::alias::define diff 'delta'
	elif command -v colordiff >/dev/null 2>&1; then
		z::alias::define diff 'colordiff'
	fi

	# Git aliases (only if git is available)
	if command -v git >/dev/null 2>&1; then
		z::alias::define g    'git'
		z::alias::define ga   'git add'
		z::alias::define gaa  'git add --all'
		z::alias::define gap  'git add --patch'
		z::alias::define gs   'git status -sb'
		z::alias::define gss  'git status'
		z::alias::define gc   'git commit -v'
		z::alias::define gca  'git commit -v --amend'
		z::alias::define gcane 'git commit -v --amend --no-edit'
		z::alias::define gco  'git checkout'
		z::alias::define gcb  'git checkout -b'
		z::alias::define gcm  'git checkout $(git symbolic-ref refs/remotes/origin/HEAD | sed "s@^refs/remotes/origin/@@")'
		z::alias::define gcd  'git checkout develop'
		z::alias::define gp   'git push'
		z::alias::define gpf  'git push --force-with-lease'
		z::alias::define gpu  'git push -u origin HEAD'
		z::alias::define gpl  'git pull --rebase --autostash'
		z::alias::define gpr  'git pull --rebase'
		z::alias::define gf   'git fetch --all --prune --tags'
		z::alias::define gr   'git rebase'
		z::alias::define gra  'git rebase --abort'
		z::alias::define grc  'git rebase --continue'
		z::alias::define grs  'git rebase --skip'
		z::alias::define gm   'git merge'
		z::alias::define gma  'git merge --abort'
		z::alias::define gmc  'git merge --continue'
		z::alias::define gl   "git log --oneline --graph --decorate --all -20"
		z::alias::define glog "git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
		z::alias::define gll  'git log --stat --max-count=5'
		z::alias::define gd   'git diff'
		z::alias::define gds  'git diff --staged'
		z::alias::define gsh  'git show'
		z::alias::define gb   'git branch'
		z::alias::define gba  'git branch -a'
		z::alias::define gbd  'git branch -d'
		z::alias::define gbD  'git branch -D'
		z::alias::define gbr  'git branch -r'
		z::alias::define gbm  'git branch --merged | grep -vE "^\*?\s*(master|main|develop)$" | xargs -n 1 git branch -d'
		z::alias::define gst  'git stash'
		z::alias::define gstp 'git stash pop'
		z::alias::define gstd 'git stash drop'
		z::alias::define gsts 'git stash show -p'
		z::alias::define gsl  'git stash list'
		z::alias::define gcl  'git clean -fd'
		z::alias::define gcaa 'git commit -v --amend --no-edit && git push --force-with-lease'
		z::alias::define greset 'git reset HEAD~'
	else
		z::log::debug "Git not available, skipping git aliases"
	fi

	# Utility aliases
	z::alias::define up   'cd ..'
	z::alias::define up2  'cd ../..'
	z::alias::define up3  'cd ../../..'
	z::alias::define up4  'cd ../../../..'
	z::alias::define cd-  'cd -'
	z::alias::define home 'cd ~'

	z::alias::define c  'clear'
	z::alias::define h  'history 1'
	z::alias::define hg 'history 1 | grep'  # note: overrides Mercurial 'hg' if installed
	z::alias::define q  'exit'
	z::alias::define job 'jobs -l'

	if ((! IS_MACOS)); then
		z::alias::define chown 'chown --preserve-root'
		z::alias::define chmod 'chmod --preserve-root'
		z::alias::define chgrp 'chgrp --preserve-root'
	fi

	if command -v curl >/dev/null 2>&1; then
		z::alias::define myip 'curl -s4 ifconfig.me/ip || curl -s4 ipinfo.io/ip || echo "IP lookup failed"'
	fi

	if command -v tar >/dev/null 2>&1; then
		z::alias::define tarx  'tar -xzvf'
		z::alias::define tarc  'tar -czvf'
		z::alias::define tarjx 'tar -xjvf'
		z::alias::define tarjc 'tar -cjvf'
		z::alias::define tarjt 'tar -tjvf'
	fi

	# Process/ports helpers (BSD vs GNU grep handling)
	if command -v ggrep >/dev/null 2>&1; then
		z::alias::define psg 'ps aux | ggrep -v grep | ggrep -iE --color=auto'
	else
		z::alias::define psg 'ps aux | grep -v grep | grep -iE'
	fi
	if command -v ss >/dev/null 2>&1; then
		z::alias::define ports 'ss -tulnp'
	elif command -v netstat >/dev/null 2>&1; then
		z::alias::define ports 'netstat -tulnp'
	fi

	z::alias::define md 'mkdir -p'
	z::alias::define rd 'rmdir'

	# Platform-specific aliases
	if (( IS_MACOS )); then
		z::alias::define flushdns 'sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder'
		z::alias::define showfiles 'defaults write com.apple.finder AppleShowAllFiles YES && killall Finder'
		z::alias::define hidefiles 'defaults write com.apple.finder AppleShowAllFiles NO && killall Finder'
		z::alias::define cleanupds 'find . -type f -name ".DS_Store" -ls -delete'
		z::alias::define brewup 'brew update && brew upgrade && brew outdated && brew autoremove && brew cleanup --prune=all && brew doctor && brew bundle dump --force && echo "Brew update complete. Consider committing Brewfile changes."'
		z::alias::define lock 'pmset displaysleepnow'

		z::alias::define desktop   'cd ~/Desktop'
		z::alias::define downloads 'cd ~/Downloads'
		z::alias::define documents 'cd ~/Documents'

		z::alias::define cpu 'sysctl -n machdep.cpu.brand_string'
	elif (( IS_LINUX )); then
		z::alias::define open 'xdg-open'
		if command -v xclip >/dev/null 2>&1; then
			z::alias::define pbcopy 'xclip -selection clipboard'
			z::alias::define pbpaste 'xclip -selection clipboard -o'
		elif command -v wl-copy >/dev/null 2>&1 && command -v wl-paste >/dev/null 2>&1; then
			z::alias::define pbcopy 'wl-copy'
			z::alias::define pbpaste 'wl-paste'
		fi
		if command -v locate >/dev/null 2>&1; then
			z::alias::define updatedb 'sudo updatedb'
		fi

		if command -v apt >/dev/null 2>&1; then
			z::alias::define aptup 'sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y && sudo apt clean'
			z::alias::define apti  'sudo apt install'
			z::alias::define apts  'apt search'
			z::alias::define aptrm 'sudo apt remove'
		elif command -v dnf >/dev/null 2>&1; then
			z::alias::define dnfup 'sudo dnf upgrade -y && sudo dnf autoremove -y && sudo dnf clean all'
			z::alias::define dnfi  'sudo dnf install'
			z::alias::define dnfs  'dnf search'
			z::alias::define dnfrm 'sudo dnf remove'
		elif command -v pacman >/dev/null 2>&1; then
			z::alias::define pacup 'sudo pacman -Syu --noconfirm'
			z::alias::define paci  'sudo pacman -S --noconfirm'
			z::alias::define pacs  'pacman -Ss'
			z::alias::define pacrm 'sudo pacman -Rns --noconfirm'
		fi
		z::alias::define distro 'cat /etc/*release | grep PRETTY_NAME | cut -d "=" -f 2- | tr -d "\"" || lsb_release -ds 2>/dev/null || echo "N/A"'
		z::alias::define kernel 'uname -r'
	fi

	z::log::debug "Aliases setup completed successfully"
	return 0
}
