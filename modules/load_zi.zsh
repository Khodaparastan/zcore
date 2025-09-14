#!/usr/bin/env zsh
_install_zi() {
	emulate -L zsh

	z::runtime::check_interrupted || return $?

	typeset -g ZI_HOME="${ZI_HOME:-$XDG_DATA_HOME/zi}"
	typeset -g ZI_BIN_DIR="$ZI_HOME/bin"
	typeset -g ZI_SCRIPT="$ZI_BIN_DIR/zi.zsh"

	if [[ -f $ZI_SCRIPT ]]; then
		if z::path::source "$ZI_SCRIPT"; then
			if (( ${+_comps} )) && [[ -f $ZI_HOME/completions/_zi ]]; then
				_comps[zi]="$ZI_HOME/completions/_zi"
				z::log::debug "ZI completions loaded"
			fi
			z::log::debug "ZI already installed at: $ZI_HOME"
			return 0
		else
			z::log::warn "Failed to source existing ZI script"
		fi
	fi

	if ! _check_network 3; then
		z::log::warn "No network connectivity. Skipping ZI installation."
		return 1
	fi

	z::log::info "Installing ZI plugin manager to $ZI_HOME..."
	if ! mkdir -p -m 755 -- "$ZI_BIN_DIR" 2>/dev/null; then
		z::log::error "Cannot create ZI directory: $ZI_BIN_DIR"
		return 1
	fi

	if command git clone --depth 1 --single-branch \
	  "https://github.com/z-shell/zi.git" "$ZI_BIN_DIR" >/dev/null 2>&1; then
		if [[ -f $ZI_SCRIPT ]]; then
			if z::path::source "$ZI_SCRIPT"; then
				z::log::info "ZI installed successfully."
				return 0
			else
				z::log::error "Failed to source newly installed ZI script"
			fi
		else
			z::log::error "ZI cloned, but zi.zsh script not found at $ZI_SCRIPT"
		fi
	else
		z::log::error "ZI installation (git clone) failed."
	fi

	[[ -d $ZI_HOME ]] && rm -rf -- "$ZI_HOME" 2>/dev/null
	return 1
}

_load_plugins() {
	emulate -L zsh

	z::runtime::check_interrupted || return $?

	(( ! ${+functions[zi]} )) && return 1

	zstyle :plugin:history-search-multi-word reset-prompt-protect 1
	zstyle ":history-search-multi-word" page-size "8"

	typeset -gAx HSMW_HIGHLIGHT_STYLES
	HSMW_HIGHLIGHT_STYLES[path]="bg=magenta,fg=white,bold"

	zi light z-shell/z-a-eval
	zi light z-shell/z-a-patch-dl
	zi light z-shell/z-a-linkbin
	zi light-mode for z-shell/z-a-unscope
	zi light z-shell/z-a-default-ice
	zi light z-shell/z-a-bin-gem-node
	zi load z-shell/zbrowse
	zi ice wait"0" as"command" pick"cmds/zc-bg-notify" silent
	zi light z-shell/zconvey
	zmodload zsh/curses
	zi wait lucid for z-shell/zi-console

	zi nocd for \
	  atload'!promptinit; typeset -g PSSHORT=0; prompt sprint3 yellow red green blue' \
	  z-shell/zprompts

	zi load z-shell/zsh-editing-workbench

	zi wait lucid for \
	  atinit"ZI[COMPINIT_OPTS]=-C; zicompinit; zicdreplay" \
	  z-shell/F-Sy-H \
	  blockf \
	  zsh-users/zsh-completions \
	  atload"!_zsh_autosuggest_start" \
	  zsh-users/zsh-autosuggestions

	zi lucid light-mode for \
	  z-shell/z-a-meta-plugins \
	  @annexes+ @zunit @z-shell @z-shell+ \
	  @zsh-users @zsh-users+fast @fuzzy \
	  skip'vivid hyperfine' @sharkdp \
	  skip'vivid exa hyperfine tig' @console-tools

	zi ice pick"h.sh"
	zi light paoloantinori/hhighlighter

	zi ice as'program' from'gh-r' mv'direnv* -> direnv'
	zi light direnv/direnv

	zi wait lucid for as'command' from'gh-r' sbin'grex' pemistahl/grex

	zi wait lucid for as"command" from"gh-r" \
	  bpick"kubectx;kubens" sbin"kubectx;kubens" \
	  ahmetb/kubectx

	zstyle :plugin:zuid codenames paper metal wood plastic
	zi load z-shell/zsh-unique-id

	zi ice eval"dircolors -b LS_COLORS" \
	  atload'zstyle ":completion:*" list-colors ${(s.:.)LS_COLORS}'
	zi light trapd00r/LS_COLORS

	zi ice as"command" pick"$ZPFX/bin/fbterm" \
	  dl"https://bugs.archlinux.org/task/46860?getfile=13513 -> ins.patch" \
	  dl"https://aur.archlinux.org/cgit/aur.git/plain/0001-Fix-build-with-gcc-6.patch?h=fbterm-git" \
	  patch"ins.patch; 0001-Fix-build-with-gcc-6.patch" \
	  atclone"./configure --prefix=$ZPFX" \
	  atpull"%atclone" make"install" reset
	zi load izmntuk/fbterm

	zi pack for @asciidoctor
	zi pack for dircolors-material
	zi pack for doctoc
	zi pack"bgn+keys" for fzf
	zi pack for ls_colors

	zi load z-shell/zsh-cmd-architect
	zi load z-shell/zsh-navigation-tools
	zi load z-shell/zsh-select
	zi light z-shell/H-S-MW

	zi ice as'null' sbin'bin/*'
	zi light z-shell/zsh-diff-so-fancy

	zi ice lucid wait as'program' from"gh-r" has'fzf'
	zi light denisidoro/navi

	zi ice lucid wait as'program' pick'prettyping' has'ping'
	zi light denilsonsa/prettyping

	zi ice wait'1' lucid
	zi load hlissner/zsh-autopair

	zi ice id-as"rust" as'completion' lucid nocompile \
	  atload="[[ ! -f \${ZPFX}/completions/_cargo || ! -f \${ZPFX}/completions/_rustup ]] && zi creinstall -q rust" for \
	  z-shell/rust

	typeset -gA HSMW_HIGHLIGHT_STYLES
	HSMW_HIGHLIGHT_STYLES[single-hyphen-option]="fg=cyan"
	HSMW_HIGHLIGHT_STYLES[double-hyphen-option]="fg=cyan"
	HSMW_HIGHLIGHT_STYLES[commandseparator]="fg=241,bg=17"

	z::log::debug "ZI plugins loaded successfully"
}
