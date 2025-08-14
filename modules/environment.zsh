# environment.zsh

_detect_platform() {
  emulate -L zsh
  [[ -n ${_PLATFORM_DETECTED:-} ]] && return 0

  if ! command -v uname >/dev/null 2>&1; then
    print -u2 "Warning: uname command not available. Platform detection might be inaccurate."
  fi

  typeset -gx PLATFORM="${OSTYPE%%[0-9]*}"
  typeset -gx ARCH="${HOSTTYPE:-$(uname -m 2>/dev/null || echo 'unknown')}"

  local is_macos=0 is_linux=0 is_arm=0
  [[ $PLATFORM == "darwin" ]] && is_macos=1
  [[ $PLATFORM == linux* ]]    && is_linux=1
  [[ $ARCH == (arm64|aarch64) ]] && is_arm=1

  typeset -grix IS_MACOS=$is_macos
  typeset -grix IS_LINUX=$is_linux
  typeset -grix IS_ARM=$is_arm

  typeset -gx _PLATFORM_DETECTED=1
  return 0
}

_detect_homebrew() {
  emulate -L zsh
  if [[ -n ${HOMEBREW_PREFIX:-} && -x $HOMEBREW_PREFIX/bin/brew ]]; then
    return 0
  fi

  (( IS_MACOS )) || return 1

  local -a search_paths=()
  (( IS_ARM )) && search_paths+=("/opt/homebrew")
  search_paths+=("/usr/local")

  local p
  for p in "${search_paths[@]}"; do
    if [[ -x $p/bin/brew ]]; then
      typeset -gx HOMEBREW_PREFIX="$p"
      return 0
    fi
  done
  return 1
}

_setup_package_managers() {
  emulate -L zsh
  if (( IS_MACOS )) && command -v brew >/dev/null 2>&1; then
    typeset -gx HOMEBREW_NO_ANALYTICS=1
    typeset -gx HOMEBREW_NO_AUTO_UPDATE=1
    typeset -gx HOMEBREW_NO_INSTALL_CLEANUP=1
    typeset -gx HOMEBREW_BUNDLE_NO_LOCK=1
    typeset -gx HOMEBREW_NO_EMOJI=1
  fi

  if command -v apt >/dev/null 2>&1; then
    typeset -gx DEBIAN_FRONTEND=noninteractive
  fi

  if command -v pacman >/dev/null 2>&1; then
    typeset -gx PACMAN_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pacman/pkg"
    [[ ! -d $PACMAN_CACHE_DIR ]] && mkdir -p -- "$PACMAN_CACHE_DIR" 2>/dev/null
  fi
}

_create_xdg_dirs() {
  emulate -L zsh
  # Ensure XDG variables are set
  if [[ -z $XDG_CONFIG_HOME || -z $XDG_DATA_HOME || -z $XDG_CACHE_HOME || -z $XDG_STATE_HOME ]]; then
    _setup_xdg || return 1
  fi

  local -a dirs=(
    "$XDG_CONFIG_HOME:700"
    "$XDG_DATA_HOME:700"
    "$XDG_CACHE_HOME:700"
    "$XDG_STATE_HOME:700"
    "$XDG_CONFIG_HOME/zsh:700"
    "$XDG_CACHE_HOME/zsh:700"
    "$XDG_STATE_HOME/zsh:700"
    "$XDG_CONFIG_HOME/ssh:700"
  )

  local entry dir perm
  for entry in "${dirs[@]}"; do
    dir="${entry%:*}"
    perm="${entry#*:}"
    [[ -d $dir ]] || mkdir -p -- "$dir" 2>/dev/null
    chmod "$perm" -- "$dir" 2>/dev/null
  done
}

_setup_xdg() {
  emulate -L zsh
  if [[ -z $HOME ]]; then
    print -u2 "ERROR: HOME environment variable is not set"
    return 1
  fi

  typeset -gx XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
  typeset -gx XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
  typeset -gx XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
  typeset -gx XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
  return 0
}

_initialize_environment() {
  emulate -L zsh
  _setup_xdg || return 1
  _detect_platform || return 1
  _create_xdg_dirs
  _detect_homebrew
  _setup_package_managers || return 1

  if [[ ${ZSH_DEBUG:-0} == 1 ]]; then
    print "Core environment initialized:"
    print "  Platform: $PLATFORM ($ARCH), IS_MACOS: $IS_MACOS, IS_LINUX: $IS_LINUX, IS_ARM: $IS_ARM"
    print "  XDG Config: $XDG_CONFIG_HOME"
    print "  XDG Data: $XDG_DATA_HOME"
    print "  XDG Cache: $XDG_CACHE_HOME"
    print "  XDG State: $XDG_STATE_HOME"
    print "  Homebrew Prefix: ${HOMEBREW_PREFIX:-Not Found}"
  fi
  return 0
}

_safe_exec() {
  emulate -L zsh
  local cmd="$1"
  [[ $# -eq 0 ]] && return 1
  shift

  if command -v "$cmd" >/dev/null 2>&1; then
    command "$cmd" "$@"
    return $?
  else
    return 127
  fi
}

_check_network() {
  emulate -L zsh
  local timeout="${1:-2}"
  local -a endpoints=(
    "https://1.1.1.1"
    "https://api.github.com/zen"
    "https://httpbin.org/status/200"
  )

  command -v curl >/dev/null 2>&1 || return 1

  local endpoint
  for endpoint in "${endpoints[@]}"; do
    if command curl -fsSL --connect-timeout "$timeout" --max-time $((timeout + 1)) \
      --retry 1 --retry-delay 0 "$endpoint" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

_setup_environment() {
  emulate -L zsh

  _setup_editor_environment() {
    emulate -L zsh
    local editor_preference
    if [[ -n $SSH_CONNECTION ]]; then
      if command -v vim >/dev/null 2>&1; then
        editor_preference="vim"
      elif command -v vi >/dev/null 2>&1; then
        editor_preference="vi"
      else
        editor_preference="vi"
      fi
    else
      if command -v nvim >/dev/null 2>&1; then
        editor_preference="nvim"
      elif command -v vim >/dev/null 2>&1; then
        editor_preference="vim"
      elif command -v vi >/dev/null 2>&1; then
        editor_preference="vi"
      else
        editor_preference="vi"
      fi
    fi
    typeset -gx EDITOR="$editor_preference"
    typeset -gx VISUAL="$EDITOR"
    typeset -gx SUDO_EDITOR="$EDITOR"
    typeset -gx GIT_EDITOR="$EDITOR"
  }

  _setup_development_environment() {
    emulate -L zsh
    if command -v go >/dev/null 2>&1; then
      typeset -gx GOPATH="${GOPATH:-$HOME/go}"
      typeset -gx GOBIN="$GOPATH/bin"
      local -a go_dirs=("$GOPATH" "$GOPATH/src" "$GOPATH/bin" "$GOPATH/pkg")
      local d; for d in "${go_dirs[@]}"; do [[ -d $d ]] || mkdir -p -- "$d" 2>/dev/null; done
    fi

    if command -v cargo >/dev/null 2>&1 || [[ -d $HOME/.cargo ]]; then
      typeset -gx CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
      typeset -gx RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
      typeset -gx CARGO_INCREMENTAL=1
      typeset -gx RUST_BACKTRACE=1
    fi

    if command -v node >/dev/null 2>&1; then
      typeset -gx NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-$HOME/.npm-global}"
      [[ -d $NPM_CONFIG_PREFIX ]] || mkdir -p -- "$NPM_CONFIG_PREFIX" 2>/dev/null
    fi

    if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
      typeset -gx PYTHONDONTWRITEBYTECODE=1
      typeset -gx PYTHONUNBUFFERED=1
      typeset -gx PIP_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pip"
      typeset -gx PIPENV_VENV_IN_PROJECT=1
      [[ -d $PIP_CACHE_DIR ]] || mkdir -p -- "$PIP_CACHE_DIR" 2>/dev/null
    fi

    if command -v java >/dev/null 2>&1; then
      if [[ -z $JAVA_HOME ]]; then
        if (( IS_MACOS )) && [[ -x /usr/libexec/java_home ]]; then
          typeset -gx JAVA_HOME="$(/usr/libexec/java_home 2>/dev/null)"
        elif (( IS_LINUX )); then
          local -a java_paths=(
            "/usr/lib/jvm/default-java"
            "/usr/lib/jvm/java-17-openjdk-amd64"
            "/usr/lib/jvm/java-11-openjdk-amd64"
            "/usr/lib/jvm/java-8-openjdk-amd64"
          )
          local jpath
          for jpath in "${java_paths[@]}"; do
            if [[ -d $jpath ]]; then
              typeset -gx JAVA_HOME="$jpath"
              break
            fi
          done
        fi
      fi
      typeset -gx MAVEN_OPTS="${MAVEN_OPTS:--Xmx1024m -XX:MaxMetaspaceSize=256m}"
      typeset -gx M2_HOME="${M2_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/maven}"
      [[ -d $M2_HOME ]] || mkdir -p -- "$M2_HOME" 2>/dev/null
    fi

    if command -v docker >/dev/null 2>&1; then
      typeset -gx DOCKER_BUILDKIT=1
      typeset -gx COMPOSE_DOCKER_CLI_BUILD=1
    fi
  }

  _setup_xdg_compliance() {
    emulate -L zsh
    local state_dir="$XDG_STATE_HOME"
    local cache_dir="$XDG_CACHE_HOME"
    local config_dir="$XDG_CONFIG_HOME"
    local -a xdg_app_dirs=(
      "$state_dir/zsh" "$cache_dir/zsh" "$config_dir/zsh"
      "$config_dir/git"
      "$config_dir/wget" "$config_dir/curl"
      "$config_dir/less" "$state_dir/less"
      "$cache_dir/pip"
      "$config_dir/maven"
      "$config_dir/readline"
    )
    local d; for d in "${xdg_app_dirs[@]}"; do [[ -n $d && -d $d ]] || mkdir -p -- "$d" 2>/dev/null; done

    typeset -gx HISTFILE="$XDG_STATE_HOME/zsh/history"
    if [[ ! -d ${HISTFILE:h} ]]; then
      mkdir -p -m 700 -- "${HISTFILE:h}" 2>/dev/null
    else
      chmod 700 -- "${HISTFILE:h}" 2>/dev/null
    fi

    typeset -gx NODE_REPL_HISTORY="$XDG_STATE_HOME/node_repl_history"
    typeset -gx PYTHON_HISTORY="$XDG_STATE_HOME/python_history"
    typeset -gx PYTHONHISTFILE="$PYTHON_HISTORY"
    typeset -gx SQLITE_HISTORY="$XDG_STATE_HOME/sqlite_history"
    typeset -gx MYSQL_HISTFILE="$XDG_STATE_HOME/mysql_history"
    typeset -gx PSQL_HISTORY="$XDG_STATE_HOME/psql_history"
    typeset -gx REDISCLI_HISTFILE="$XDG_STATE_HOME/redis_history"

    typeset -gx LESSHISTFILE="$XDG_STATE_HOME/less/history"
    typeset -gx WGETRC="$XDG_CONFIG_HOME/wget/wgetrc"
    typeset -gx CURL_HOME="$XDG_CONFIG_HOME/curl"
    typeset -gx INPUTRC="$XDG_CONFIG_HOME/readline/inputrc"

    typeset -gx GIT_CONFIG_GLOBAL="$XDG_CONFIG_HOME/git/config"
  }

  _setup_security_environment() {
    emulate -L zsh
    if command -v gpg >/dev/null 2>&1 || command -v gpg2 >/dev/null 2>&1; then
      typeset -gx GNUPGHOME="${XDG_DATA_HOME:-$HOME/.local/share}/gnupg"
      if [[ ! -d $GNUPGHOME ]]; then
        mkdir -p -m 700 -- "$GNUPGHOME" 2>/dev/null
      else
        chmod 700 -- "$GNUPGHOME" 2>/dev/null
      fi
      if [[ -t 0 ]]; then
        typeset -gx GPG_TTY="$(tty 2>/dev/null || echo '/dev/tty')"
      fi
    fi
  }

  _setup_performance_environment() {
    emulate -L zsh
    if command -v make >/dev/null 2>&1; then
      local cores
      if (( IS_MACOS )); then
        cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 2)
      else
        cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 2)
      fi
      typeset -gx MAKEFLAGS="-j${cores}"
    fi
  }

  _setup_terminal_environment() {
    emulate -L zsh
    typeset -gx LANG="${LANG:-en_US.UTF-8}"
    typeset -gx LC_ALL="${LC_ALL:-$LANG}"
    typeset -gx TERM="${TERM:-xterm-256color}"
    typeset -gx COLORTERM="${COLORTERM:-truecolor}"

    if command -v less >/dev/null 2>&1; then
      typeset -gx PAGER="less"
      # Trim to widely-supported flags
      typeset -gx LESS="-R -Si -M -j.5"

      if command -v lesspipe.sh >/dev/null 2>&1; then
        typeset -gx LESSOPEN="|lesspipe.sh %s"
      elif command -v src-hilite-lesspipe.sh >/dev/null 2>&1; then
        typeset -gx LESSOPEN="|src-hilite-lesspipe.sh %s"
        typeset -gx LESSCOLOR=always
        command -v pygmentize >/dev/null 2>&1 && typeset -gx LESSCOLORIZER=pygmentize
      fi
    fi

    typeset -gx LESS_TERMCAP_mb=$'\e[1;32m'
    typeset -gx LESS_TERMCAP_md=$'\e[1;36m'
    typeset -gx LESS_TERMCAP_me=$'\e[0m'
    typeset -gx LESS_TERMCAP_so=$'\e[01;44;33m'
    typeset -gx LESS_TERMCAP_se=$'\e[0m'
    typeset -gx LESS_TERMCAP_us=$'\e[1;4;31m'
    typeset -gx LESS_TERMCAP_ue=$'\e[0m'
  }

  _setup_cloud_environment() {
    emulate -L zsh
    if command -v aws >/dev/null 2>&1; then
      typeset -gx AWS_CLI_AUTO_PROMPT=on-partial
      typeset -gx AWS_PAGER=""
    fi
    if command -v terraform >/dev/null 2>&1; then
      local cores
      if (( IS_MACOS )); then
        cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 10)
      else
        cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 10)
      fi
      typeset -gx TF_CLI_ARGS_plan="-parallelism=${cores}"
      typeset -gx TF_CLI_ARGS_apply="-parallelism=${cores}"
    fi
    if command -v kubectl >/dev/null 2>&1 && command -v delta >/dev/null 2>&1; then
      typeset -gx KUBECTL_EXTERNAL_DIFF="delta --syntax-highlight --paging=never"
    fi
  }

  _setup_editor_environment
  _setup_development_environment
  _setup_xdg_compliance
  _setup_security_environment
  _setup_performance_environment
  _setup_terminal_environment
  _setup_cloud_environment

  return 0
}

