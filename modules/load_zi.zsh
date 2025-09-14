#!/usr/bin/env zsh
#
# ZI Plugin Manager Module
# Handles the installation and configuration of the ZI plugin manager and its plugins.
#

# ==============================================================================
# PRIVATE HELPERS
# ==============================================================================

###
# Checks for network connectivity by pinging a reliable public DNS server.
#
# @param 1: integer - Timeout in seconds (default: 3).
# @return 0 on success, 1 on failure.
###
z::zi::_check_network() {
	emulate -L zsh
	local -i timeout=${1:-3}
	local host="8.8.8.8" # Google's public DNS

	if ! z::cmd::exists "ping"; then
		z::log::warn "ping command not found, cannot check network status."
		return 1
	fi

	# Use flags compatible with both macOS/BSD and Linux ping
	if ping -c 1 -W "${timeout}000" "$host" >/dev/null 2>&1 || \
	   ping -c 1 -t "$timeout" "$host" >/dev/null 2>&1; then
		return 0
	fi
	return 1
}

###
# Installs the ZI plugin manager if it's not already present.
###
z::zi::_install() {
	emulate -L zsh
	z::runtime::check_interrupted || return $?

	typeset -g ZI_HOME="${ZI_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/zi}"
	typeset -g ZI_BIN_DIR="$ZI_HOME/bin"
	typeset -g ZI_SCRIPT="$ZI_BIN_DIR/zi.zsh"

	if [[ -f "$ZI_SCRIPT" ]]; then
		if z::path::source "$ZI_SCRIPT"; then
			z::log::debug "ZI already installed and sourced from: $ZI_HOME"
			return 0
		else
			z::log::error "Found ZI script at $ZI_SCRIPT but failed to source it."
			return 1
		fi
	fi

	z::log::info "ZI plugin manager not found. Attempting installation..."

	if ! z::zi::_check_network 3; then
		z::log::warn "No network connectivity. Skipping ZI installation."
		return 1
	fi

	if ! z::cmd::exists "git"; then
		z::log::error "git is required to install ZI, but it was not found."
		return 1
	fi

	z::log::info "Installing ZI to $ZI_HOME..."
	if ! command git clone --depth 1 --single-branch \
		"https://github.com/z-shell/zi.git" "$ZI_BIN_DIR" >/dev/null 2>&1; then
		z::log::error "ZI installation (git clone) failed."
		[[ -d "$ZI_HOME" ]] && command rm -rf -- "$ZI_HOME" 2>/dev/null
		return 1
	fi

	if [[ -f "$ZI_SCRIPT" ]]; then
		if z::path::source "$ZI_SCRIPT"; then
			z::log::info "ZI installed and sourced successfully."
			return 0
		else
			z::log::error "Failed to source newly installed ZI script."
			return 1
		fi
	else
		z::log::error "ZI cloned, but zi.zsh script not found at expected path: $ZI_SCRIPT"
		return 1
	fi
}

###
# Loads all user-defined plugins and configurations using ZI.
###
z::zi::_load_plugins() {
	emulate -L zsh
	z::runtime::check_interrupted || return $?

	(( ! ${+functions[zi]} )) && return 1

	# --- Begin User Plugin Configuration ---

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
	# zi light z-shell/zconvey
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

	# --- End User Plugin Configuration ---

	z::log::debug "ZI plugins loaded successfully"
	return 0
}


# ==============================================================================
# MAIN INITIALIZATION ORCHESTRATOR
# ==============================================================================

###
# Public entry point to install ZI and load all configured plugins.
###
z::zi::init() {
	emulate -L zsh
	z::runtime::check_interrupted || return $?
	z::log::info "Initializing ZI plugin manager module..."

	if z::zi::_install; then
		z::zi::_load_plugins
	else
		z::log::error "ZI installation failed. Cannot load plugins."
		return 1
	fi

	z::log::info "ZI module initialized successfully."
	return 0
}

# ==============================================================================
# MODULE EXECUTION
# ==============================================================================

# Auto-initialize the module when it is sourced.
if z::func::exists "z::zi::init"; then
	z::zi::init
fi
