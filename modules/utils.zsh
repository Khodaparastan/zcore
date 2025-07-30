_setup_colors() {
    if (( IS_MACOS )); then
        typeset -grx LSCOLORS='exfxcxdxbxegedAbAgacad'
        typeset -grx CLICOLOR=1
    else
        if [[ -z "$LS_COLORS" ]] && command -v dircolors >/dev/null 2>&1; then
            eval "$(dircolors -b)"
        elif [[ -z "$LS_COLORS" ]]; then
            typeset -grx LS_COLORS='rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:mi=00:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=34;42:st=37;44:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arj=01;31:*.taz=01;31:*.lzh=01;31:*.lzma=01;31:*.tlz=01;31:*.txz=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.dz=01;31:*.gz=01;31:*.lz=01;31:*.xz=01;31:*.bz2=01;31:*.bz=01;31:*.tbz=01;31:*.tbz2=01;31:*.tz=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.war=01;31:*.ear=01;31:*.sar=01;31:*.rar=01;31:*.alz=01;31:*.ace=01;31:*.zoo=01;31:*.cpio=01;31:*.7z=01;31:*.rz=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.svg=01;35:*.svgz=01;35:*.mng=01;35:*.pcx=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.m2v=01;35:*.mkv=01;35:*.webm=01;35:*.ogm=01;35:*.mp4=01;35:*.m4v=01;35:*.mp4v=01;35:*.vob=01;35:*.qt=01;35:*.nuv=01;35:*.wmv=01;35:*.asf=01;35:*.rm=01;35:*.rmvb=01;35:*.flc=01;35:*.avi=01;35:*.fli=01;35:*.flv=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.yuv=01;35:*.cgm=01;35:*.emf=01;35:*.axv=01;35:*.anx=01;35:*.ogv=01;35:*.ogx=01;35:*.aac=00;36:*.au=00;36:*.flac=00;36:*.mid=00;36:*.midi=00;36:*.mka=00;36:*.mp3=00;36:*.mpc=00;36:*.ogg=00;36:*.ra=00;36:*.wav=00;36:'
        fi
    fi
}

_setup_ls() {
    _setup_colors

    local ls_tool="system"

    if command -v eza >/dev/null 2>&1; then
        ls_tool="eza"
        local -a eza_base_opts=(--group-directories-first --color=always --classify)
        if eza --icons --long /dev/null >/dev/null 2>&1; then
            eza_base_opts+=(--icons)
        fi

        local eza_cmd="eza ${(j: :)eza_base_opts[@]}"
        alias ls="$eza_cmd"
        alias ll="$eza_cmd --long --header --git --time-style=long-iso --total-size"
        alias la="$eza_cmd --all" # Show hidden files, but not . and ..
        alias l="$eza_cmd --all --long --header --git --time-style=long-iso --total-size"
        alias lt="$eza_cmd --tree --level=3 --long --git" # Tree view

    elif command -v lsd >/dev/null 2>&1; then
        ls_tool="lsd"
        alias ls="lsd --group-directories-first --color=always --icon=auto --classify"
        alias ll="lsd --long --header --date=long-iso --size=short --blocks=permission,user,group,size,date,name,git --total-size"
        alias la="lsd --almost-all" # Show hidden files, but not . and ..
        alias l="lsd --almost-all --long --header --date=long-iso --size=short --blocks=permission,user,group,size,date,name,git --total-size"
        alias lt="lsd --tree --depth=3 --long"

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
        alias ls="$ls_cmd_base"
        alias ll="$ls_cmd_base -lh"
        alias la="$ls_cmd_base -A"
        alias l="$ls_cmd_base -Alh"
    fi
    typeset -gx LS_TOOL="$ls_tool"
}

_setup_tree_fallback() {
    typeset -g _ZSH_TREE_FALLBACK_DEFINED=0

    if ! command -v tree >/dev/null 2>&1; then
        _ZSH_TREE_FALLBACK_DEFINED=1

        tree() {
            local dir="${1:-.}"
            local max_depth="${2:-3}"

            if [[ ! -d "$dir" ]]; then
                print -u2 "tree: '$dir': No such directory or not a directory."
                return 1
            fi

            if [[ ! "$max_depth" =~ ^[1-9][0-9]*$ ]] || (( max_depth > 10 || max_depth < 1 )); then
                print -u2 "tree: invalid depth '$max_depth'. Please use a number between 1 and 10."
                return 1
            fi

            dir=$(cd "$dir" && pwd) || return 1

            print -P "%F{blue}$(basename "$dir")/%f"

            local -A file_info
            local -a sorted_files
            local full_path

            while IFS= read -r -d '' full_path; do
                local relative_path="${full_path#$dir/}"
                local depth=$(( ${#${relative_path//[^\/]}} + 1 ))

                file_info[$full_path]="$depth"
                sorted_files+=("$full_path")
            done < <(find "$dir" -maxdepth "$max_depth" -not -path "$dir" -print0 2>/dev/null | sort -z)

            local -i total=${#sorted_files}
            local -i i=0

            for full_path in "${sorted_files[@]}"; do
                (( i++ ))
                local base_name="${full_path:t}"
                local depth=${file_info[$full_path]}
                local relative_path="${full_path#$dir/}"

                local indent=""
                local -i j=1
                while (( j < depth )); do
                    indent+="  "
                    (( j++ ))
                done

                local prefix="├──"
                if (( i == total )); then
                    prefix="└──"
                else
                    if (( i < total )); then
                        local next_path="${sorted_files[i+1]}"
                        local next_depth=${file_info[$next_path]}
                        local next_relative="${next_path#$dir/}"

                        local current_parent="${relative_path%/*}"
                        local next_parent="${next_relative%/*}"

                        if [[ "$next_parent" != "$current_parent" ]] || (( next_depth < depth )); then
                            prefix="└──"
                        fi
                    fi
                fi

                if [[ -d "$full_path" ]]; then
                    printf "%s%s %F{blue}%s/%f\n" "$indent" "$prefix" "$base_name"
                elif [[ -x "$full_path" ]]; then
                    printf "%s%s %F{green}%s*%f\n" "$indent" "$prefix" "$base_name"
                else
                    printf "%s%s %s\n" "$indent" "$prefix" "$base_name"
                fi
            done
        }
    fi
}
_setup_additional_utilities() {
    if command -v du >/dev/null 2>&1; then
        local is_bsd_du=0
        if [[ "${OSTYPE:-}" == darwin* ]] || du --version 2>&1 | grep -q "illegal option"; then
            is_bsd_du=1
        fi

    fi

    if command -v find >/dev/null 2>&1 && command -v stat >/dev/null 2>&1; then
        newest() {
            local count="${1:-10}" path="${2:-.}"

            if [[ ! "$count" =~ ^[1-9][0-9]*$ ]] || (( count > 100 || count < 1 )); then
                print -u2 "newest: invalid count '$count'. Use 1-100."
                return 1
            fi

            if [[ ! -d "$path" ]]; then
                print -u2 "newest: path '$path' not found or not a directory."
                return 1
            fi

            if [[ ! -r "$path" ]]; then
                print -u2 "newest: cannot read directory '$path'."
                return 1
            fi

            local is_bsd_stat=0
            if [[ "${OSTYPE:-}" == darwin* ]] || stat --version 2>&1 | grep -q "illegal option"; then
                is_bsd_stat=1
            fi

            if (( is_bsd_stat )); then
                find "$path" -mindepth 1 -type f -print0 2>/dev/null | \
                xargs -0 stat -f "%m %N" 2>/dev/null | \
                sort -rnk1,1 | \
                head -n "$count" | \
                cut -d' ' -f2-
            else
                find "$path" -mindepth 1 -type f -print0 2>/dev/null | \
                xargs -0 stat -c "%Y %n" 2>/dev/null | \
                sort -rnk1,1 | \
                head -n "$count" | \
                cut -d' ' -f2-
            fi
        }
    fi
}

_setup_smart_cd() {
    if [[ -n "${ZSH_CD_AUTO_LS:-}" ]]; then
        cd() {
            if builtin cd "$@"; then
                local item_count

                if command -v ls >/dev/null 2>&1; then
                    if item_count=$(command ls -1A 2>/dev/null | command wc -l 2>/dev/null); then
                        if (( item_count <= ${ZSH_CD_AUTO_LS_THRESHOLD:-50} )); then
                            if command -v eza >/dev/null 2>&1; then
                                eza
                            elif command -v lsd >/dev/null 2>&1; then
                                lsd
                            elif alias ls >/dev/null 2>&1; then
                                command ls --color=auto 2>/dev/null || command ls
                            else
                                command ls
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
    fi
}

