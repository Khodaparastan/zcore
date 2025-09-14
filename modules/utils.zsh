#!/usr/bin/env zsh
_setup_colors() {
    emulate -L zsh
    setopt no_unset warn_create_global

    z::runtime::check_interrupted || return $?

    if (( IS_MACOS )); then
        typeset -grx LSCOLORS='exfxcxdxbxegedAbAgacad'
        typeset -grx CLICOLOR=1
        z::log::debug "Configured macOS colors: LSCOLORS and CLICOLOR"
    else
        if [[ -z ${LS_COLORS:-} ]] && command -v dircolors >/dev/null 2>&1; then
            eval "$(dircolors -b)" 2>/dev/null || {
                # Fallback if dircolors fails
                typeset -grx LS_COLORS='rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:mi=00:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=34;42:st=37;44:ex=01;32'
                z::log::warn "dircolors failed, using fallback LS_COLORS"
            }
        elif [[ -z ${LS_COLORS:-} ]]; then
            typeset -grx LS_COLORS='rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:mi=00:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=34;42:st=37;44:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arj=01;31:*.taz=01;31:*.lzh=01;31:*.lzma=01;31:*.tlz=01;31:*.txz=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.dz=01;31:*.gz=01;31:*.lz=01;31:*.xz=01;31:*.bz2=01;31:*.bz=01;31:*.tbz=01;31:*.tbz2=01;31:*.tz=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.war=01;31:*.ear=01;31:*.sar=01;31:*.rar=01;31:*.alz=01;31:*.ace=01;31:*.zoo=01;31:*.cpio=01;31:*.7z=01;31:*.rz=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.svg=01;35:*.svgz=01;35:*.mng=01;35:*.pcx=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.m2v=01;35:*.mkv=01;35:*.webm=01;35:*.ogm=01;35:*.mp4=01;35:*.m4v=01;35:*.mp4v=01;35:*.vob=01;35:*.qt=01;35:*.nuv=01;35:*.wmv=01;35:*.asf=01;35:*.rm=01;35:*.rmvb=01;35:*.flc=01;35:*.avi=01;35:*.fli=01;35:*.flv=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.yuv=01;35:*.cgm=01;35:*.emf=01;35:*.axv=01;35:*.anx=01;35:*.ogv=01;35:*.ogx=01;35:*.aac=00;36:*.au=00;36:*.flac=00;36:*.mid=00;36:*.midi=00;36:*.mka=00;36:*.mp3=00;36:*.mpc=00;36:*.ogg=00;36:*.ra=00;36:*.wav=00;36:'
            z::log::debug "Using fallback LS_COLORS for non-macOS system"
        fi
        z::log::debug "Configured Linux/BSD colors: LS_COLORS"
    fi
}

_setup_ls() {
    emulate -L zsh
    setopt no_unset warn_create_global

    z::runtime::check_interrupted || return $?

    _setup_colors

    local ls_tool="system"

    if command -v eza >/dev/null 2>&1; then
        ls_tool="eza"
        local -a eza_base_opts=(--group-directories-first --color=always --classify)
        if eza --help 2>&1 | grep -q -- '--icons'; then
            eza_base_opts+=(--icons)
        fi
        local eza_cmd="eza ${(j: :)eza_base_opts[@]}"
        z::alias::define ls "$eza_cmd" || z::log::warn "Failed to create ls alias for eza"
        z::alias::define ll "$eza_cmd --long --header --git --time-style=long-iso --total-size" || z::log::warn "Failed to create ll alias for eza"
        z::alias::define la "$eza_cmd --all" || z::log::warn "Failed to create la alias for eza"
        z::alias::define l "$eza_cmd --all --long --header --git --time-style=long-iso --total-size" || z::log::warn "Failed to create l alias for eza"
        z::alias::define lt "$eza_cmd --tree --level=3 --long --git" || z::log::warn "Failed to create lt alias for eza"
        z::log::info "Configured eza as ls replacement"
    elif command -v lsd >/dev/null 2>&1; then
        ls_tool="lsd"
        z::alias::define ls "lsd --group-directories-first --color=always --icon=auto --classify" || z::log::warn "Failed to create ls alias for lsd"
        z::alias::define ll "lsd --long --header --date=long-iso --size=short --blocks=permission,user,group,size,date,name,git --total-size" || z::log::warn "Failed to create ll alias for lsd"
        z::alias::define la "lsd --almost-all" || z::log::warn "Failed to create la alias for lsd"
        z::alias::define l "lsd --almost-all --long --header --date=long-iso --size=short --blocks=permission,user,group,size,date,name,git --total-size" || z::log::warn "Failed to create l alias for lsd"
        z::alias::define lt "lsd --tree --depth=3 --long" || z::log::warn "Failed to create lt alias for lsd"
        z::log::info "Configured lsd as ls replacement"
    else
        local ls_cmd_base="ls"
        if (( IS_MACOS )); then
            ls_cmd_base="ls -FG"
        else
            if ls --group-directories-first /dev/null >/dev/null 2>&1; then
                ls_cmd_base="ls -F --color=auto --group-directories-first"
            else
                ls_cmd_base="ls -F --color=auto"
            fi
        fi
        z::alias::define ls "$ls_cmd_base" || z::log::warn "Failed to create ls alias"
        z::alias::define ll "$ls_cmd_base -lh" || z::log::warn "Failed to create ll alias"
        z::alias::define la "$ls_cmd_base -A" || z::log::warn "Failed to create la alias"
        z::alias::define l "$ls_cmd_base -Alh" || z::log::warn "Failed to create l alias"
        z::log::info "Configured system ls with enhanced options"
    fi

    typeset -grx LS_TOOL="$ls_tool"
    z::log::debug "LS tool configured: $ls_tool"
}

_setup_tree_fallback() {
    emulate -L zsh
    setopt no_unset warn_create_global

    z::runtime::check_interrupted || return $?

    typeset -gr _ZCORETREE_FALLBACK_DEFINED=0

    if ! command -v tree >/dev/null 2>&1; then
        typeset -gr _ZCORETREE_FALLBACK_DEFINED=1

        tree() {
            emulate -L zsh
            setopt LOCAL_OPTIONS NO_NOMATCH

            local dir="${1:-.}"
            local max_depth="${2:-3}"

            if [[ ! -d $dir ]]; then
                print -u2 "tree: '$dir': No such directory or not a directory."
                return 1
            fi
            if [[ ! $max_depth = <-> ]] || (( max_depth < 1 || max_depth > 10 )); then
                print -u2 "tree: invalid depth '$max_depth'. Please use a number between 1 and 10."
                return 1
            fi

            dir="$(cd -- "$dir" && pwd -P)" || return 1
            print -P "%F{blue}${dir:t}/%f"

            local -a files
            local full_path

            # Prefer GNU sort -z when available; otherwise keep unsorted but NUL-safe
            local have_gnu_sort=0
            if sort --version >/dev/null 2>&1; then
                have_gnu_sort=1
            fi

            if (( have_gnu_sort )); then
                while IFS= read -r -d '' full_path; do
                    files+=("$full_path")
                done < <(command find "$dir" -maxdepth "$max_depth" -mindepth 1 -print0 2>/dev/null | sort -z)
            else
                while IFS= read -r -d '' full_path; do
                    files+=("$full_path")
                done < <(command find "$dir" -maxdepth "$max_depth" -mindepth 1 -print0 2>/dev/null)
            fi

            local relative_path depth base_name indent prefix next_path next_depth next_relative current_parent next_parent
            local -i total=${#files} i=0

            for full_path in "${files[@]}"; do
                (( i++ ))
                base_name="${full_path:t}"
                relative_path="${full_path#$dir/}"
                depth=$(( ${#${relative_path//[^\/]}} + 1 ))

                indent=""
                for (( j=1; j<depth; j++ )); do
                    indent+="  "
                done

                prefix="├──"
                if (( i == total )); then
                    prefix="└──"
                else
                    next_path="${files[i]}"
                    next_relative="${next_path#$dir/}"
                    next_depth=$(( ${#${next_relative//[^\/]}} + 1 ))
                    current_parent="${relative_path%/*}"
                    next_parent="${next_relative%/*}"
                    if [[ $next_parent != $current_parent ]] || (( next_depth < depth )); then
                        prefix="└──"
                    fi
                fi

                if [[ -d $full_path ]]; then
                    print -P -- "${indent}${prefix} %F{blue}${base_name}/%f"
                elif [[ -x $full_path ]]; then
                    print -P -- "${indent}${prefix} %F{green}${base_name}*%f"
                else
                    print -- "${indent}${prefix} ${base_name}"
                fi
            done
        }
        z::log::info "Created fallback tree function"
    else
        z::log::debug "System tree command available, no fallback needed"
    fi
}

_setup_additional_utilities() {
    emulate -L zsh
    setopt no_unset warn_create_global

    z::runtime::check_interrupted || return $?

    if command -v find >/dev/null 2>&1 && command -v stat >/dev/null 2>&1; then
        newest() {
            emulate -L zsh  # Keep -L here since this is the actual function implementation
            local count="${1:-10}" path="${2:-.}"

            if [[ ! $count = <-> ]] || (( count < 1 || count > 100 )); then
                print -u2 "newest: invalid count '$count'. Use 1-100."
                return 1
            fi
            if [[ ! -d $path ]]; then
                print -u2 "newest: path '$path' not found or not a directory."
                return 1
            fi
            if [[ ! -r $path ]]; then
                print -u2 "newest: cannot read directory '$path'."
                return 1
            fi

            local z::platform::is_bsd_stat=0
            if [[ ${OSTYPE:-} == darwin* ]] || stat --version 2>&1 | grep -q "illegal option"; then
                z::platform::is_bsd_stat=1
            fi

            if (( z::platform::is_bsd_stat )); then
                find "$path" -mindepth 1 -type f -print0 2>/dev/null \
                | xargs -0 stat -f "%m %N" 2>/dev/null \
                | sort -rnk1,1 \
                | head -n "$count" \
                | cut -d' ' -f2-
            else
                find "$path" -mindepth 1 -type f -print0 2>/dev/null \
                | xargs -0 stat -c "%Y %n" 2>/dev/null \
                | sort -rnk1,1 \
                | head -n "$count" \
                | cut -d' ' -f2-
            fi
        }
        z::log::debug "Created newest utility function"
    else
        z::log::warn "find or stat not available, newest utility not created"
    fi
}

_setup_smart_cd() {
    emulate -L zsh
    setopt no_unset warn_create_global

    z::runtime::check_interrupted || return $?

    if [[ -n ${ZCORECD_AUTO_LS:-} ]]; then
        cd() {
            # Keep emulate -L here since this function needs to be self-contained
            emulate -L zsh
            if builtin cd "$@"; then
                local item_count
                if command -v ls >/dev/null 2>&1; then
                    if item_count=$(command ls -1A 2>/dev/null | command wc -l 2>/dev/null); then
                        if (( item_count <= ${ZCORECD_AUTO_LS_THRESHOLD:-50} )); then
                            if command -v eza >/dev/null 2>&1; then
                                eza
                            elif command -v lsd >/dev/null 2>&1; then
                                lsd
                            else
                                command ls || true
                            fi
                        else
                            if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && tput colors >/dev/null 2>&1; then
                                print -P "%F{yellow}Directory contains $item_count items (use 'ls' to list manually)%f"
                            else
                                print "Directory contains $item_count items (use 'ls' to list manually)"
                            fi
                        fi
                    else
                        print "Changed to: $PWD"
                    fi
                else
                    print "Changed to: $PWD"
                fi
                return 0
            else
                return $?
            fi
        }
        z::log::info "Smart CD with auto-ls enabled"
    else
        z::log::debug "Smart CD not enabled (ZCORECD_AUTO_LS not set)"
    fi
}
