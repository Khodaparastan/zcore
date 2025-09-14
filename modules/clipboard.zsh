cpfile() {
	emulate -L zsh -o no_aliases

	# Configuration (env override supported)
	local -i max_size=$((5 * 1024 * 1024))  # default 5MB
	if [[ -n ${CPFILE_MAX_SIZE:-} && ${CPFILE_MAX_SIZE} == <-> ]]; then
		max_size=$CPFILE_MAX_SIZE
	fi

	# Check arguments
	if (( $# == 0 )); then
		print -r -- "Usage: cpfile <filename>" >&2
		return 1
	fi
	if (( $# > 1 )); then
		print -r -- "Warning: Multiple files specified, processing only '$1'" >&2
	fi

	local file=$1

	# Validate file
	if [[ ! -f $file ]]; then
		print -r -- "Error: '$file' not found or not a regular file" >&2
		return 1
	fi
	if [[ ! -r $file ]]; then
		print -r -- "Error: '$file' is not readable" >&2
		return 1
	fi

	# Determine file size using the most efficient available method
	local -i file_size=-1

	if zmodload zsh/stat 2>/dev/null; then
		local -A _st
		if zstat -H _st +size -- "$file" 2>/dev/null; then
			file_size=$(( _st[size] + 0 ))
		fi
	fi

	if (( file_size < 0 )); then
		local _sz=""
		if command -v stat >/dev/null 2>&1; then
			_sz=$(stat -c %s -- "$file" 2>/dev/null || stat -f %z -- "$file" 2>/dev/null) || _sz=""
		fi
		if [[ -n $_sz ]]; then
			file_size=$(( _sz + 0 ))
		fi
	fi

	# Optional last-resort fallback (avoids skipping size check if metadata methods fail)
	if (( file_size < 0 )); then
		local _wc=""
		_wc=$(wc -c < "$file" 2>/dev/null) || _wc=""
		if [[ -n $_wc ]]; then
			file_size=$(( _wc + 0 ))
		fi
	fi

	if (( file_size >= 0 && file_size > max_size )); then
		printf "Error: File '%s' is too large (%d MB > %d MB limit)\n" \
		  "$file" "$((file_size / 1024 / 1024))" "$((max_size / 1024 / 1024))" >&2
		return 1
	fi

	# Build ordered list of clipboard utilities to try
	local -a candidates tools

	# macOS first on Darwin
	if [[ $OSTYPE == darwin* ]]; then
		candidates+=(pbcopy)
	fi
	# WSL support
	if command -v clip.exe >/dev/null 2>&1; then
		candidates+=(clip.exe)
	fi
	# TMUX clipboard (when inside tmux)
	if [[ -n ${TMUX:-} ]] && command -v tmux >/dev/null 2>&1; then
		candidates+=(tmux)
	fi
	# Prefer Wayland tools on Wayland, X11 tools on X11
	if [[ -n ${WAYLAND_DISPLAY:-} || ${XDG_SESSION_TYPE:-} == wayland ]]; then
		candidates+=(wl-copy xclip xsel)
	elif [[ -n ${DISPLAY:-} ]]; then
		candidates+=(xclip xsel wl-copy)
	else
		candidates+=(wl-copy xclip xsel)
	fi

	# Filter to installed tools and deduplicate while preserving order
	local -A seen
	local t
	for t in "${candidates[@]}"; do
		if [[ -n ${seen[$t]} ]]; then
			continue
		fi
		if command -v "$t" >/dev/null 2>&1; then
			tools+=("$t")
			seen[$t]=1
		fi
	done

	if (( ${#tools} == 0 )); then
		print -r -- "Error: No clipboard utility found" >&2
		print -r -- "Please install: pbcopy (macOS), xclip/xsel (X11), wl-copy (Wayland), clip.exe (WSL), or use tmux" >&2
		return 1
	fi

	# Try each tool until one succeeds
	local -i ok=0
	for t in "${tools[@]}"; do
		case $t in
			pbcopy)
				if pbcopy < "$file"; then ok=1; fi
				;;
			xclip)
				if xclip -selection clipboard -in < "$file"; then ok=1; fi
				;;
			xsel)
				if xsel --clipboard --input < "$file"; then ok=1; fi
				;;
			wl-copy)
				if wl-copy < "$file"; then ok=1; fi
				;;
			clip.exe)
				if clip.exe < "$file"; then ok=1; fi
				;;
			tmux)
				if tmux load-buffer -w - < "$file"; then ok=1; fi
				;;
		esac
		if (( ok )); then
			print -r -- "✓ Contents of '$file' copied to clipboard" >&2
			return 0
		fi
	done

	print -r -- "Error: Failed to copy file contents to clipboard" >&2
	return 1
}

cbf() {
	emulate -L zsh -o no_aliases
	# Back-compat wrapper for cpfile
	if (( $# == 0 )); then
		print -r -- "Usage: cbf <filename>" >&2
		return 1
	fi
	cpfile "$@"
}
