#!/usr/bin/env zsh
#
# Core environment module: stat/cpu helpers, package managers, XDG dirs,
# editor, dev toolchains, terminal, security, performance, cloud env.
#

# Load stat builtin once if available (used by helpers below).
zmodload zsh/stat 2>/dev/null

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

###
# Cross-platform stat value extractor.
# Usage: __z::mod::env::get_stat_value <mtime|uid|perms> <file>
###
__z::mod::env::get_stat_value() {
  emulate -L zsh -o no_aliases
  local format=$1 file=$2 result
  local -a st

  case "$format" in
    mtime)
      if (( ${+builtins[zstat]} )) && zstat -A st +mtime -- "$file" 2>/dev/null; then
        result=${st[1]}
      elif [[ "$OSTYPE" == darwin* ]]; then
        result=$(command stat -f %m -- "$file" 2>/dev/null)
      else
        result=$(command stat -c %Y -- "$file" 2>/dev/null)
      fi
      ;;
    uid)
      if (( ${+builtins[zstat]} )) && zstat -A st +uid -- "$file" 2>/dev/null; then
        result=${st[1]}
      elif [[ "$OSTYPE" == darwin* ]]; then
        result=$(command stat -f %u -- "$file" 2>/dev/null)
      else
        result=$(command stat -c %u -- "$file" 2>/dev/null)
      fi
      ;;
    perms)
      if (( ${+builtins[zstat]} )) && zstat -A st +mode -- "$file" 2>/dev/null; then
        # zstat returns mode as decimal -> convert to octal owner/group/other
        printf -v result '%o' $(( st[1] & 07777 ))
      elif [[ "$OSTYPE" == darwin* ]]; then
        result=$(command stat -f %Lp -- "$file" 2>/dev/null)
      else
        result=$(command stat -c %a -- "$file" 2>/dev/null)
      fi
      ;;
    *) return 1 ;;
  esac

  if [[ -z "$result" ]]; then
    print -r -- "unknown"
    return 1
  fi
  print -r -- "$result"
  return 0
}

###
# CPU core count, cached after first call.
###
__z::mod::env::get_cpu_count() {
  emulate -L zsh -o no_aliases
  if [[ -n "${_z_cpu_count:-}" ]]; then
    print -r -- "$_z_cpu_count"
    return 0
  fi

  local cores
  if [[ "$OSTYPE" == darwin* ]]; then
    cores=$(command sysctl -n hw.ncpu 2>/dev/null)
  else
    cores=$(command nproc 2>/dev/null) \
      || cores=$(command grep -c '^processor' /proc/cpuinfo 2>/dev/null)
  fi
  [[ "$cores" != <-> ]] && cores=2
  typeset -g _z_cpu_count=$cores
  print -r -- "$cores"
}

###
# Idempotent directory permission setter.
###
__z::mod::env::ensure_dir_perms() {
  emulate -L zsh -o no_aliases
  local dir=$1 want=$2 current

  [[ -d "$dir" ]] || return 0
  current=$(__z::mod::env::get_stat_value perms "$dir" 2>/dev/null)
  if [[ "$current" == "$want" ]]; then
    z::log::debug "$dir permissions already $want"
    return 0
  fi
  if command chmod "$want" -- "$dir" 2>/dev/null; then
    z::log::debug "Set permissions $want on: $dir"
  else
    z::log::debug "Could not change permissions on: $dir (current=$current)"
  fi
}

# ==============================================================================
# PACKAGE MANAGER SETUP
# ==============================================================================

__z::mod::env::setup_package_managers() {
  emulate -L zsh -o no_aliases

  if (( IS_MACOS )) && z::probe::cmd "brew"; then
    if [[ -z "${HOMEBREW_PREFIX:-}" ]]; then
      z::exec::from_hook brew shellenv
    fi
    typeset -gx HOMEBREW_NO_ANALYTICS=1
    typeset -gx HOMEBREW_NO_AUTO_UPDATE=1
    typeset -gx HOMEBREW_NO_INSTALL_CLEANUP=1
    typeset -gx HOMEBREW_BUNDLE_NO_LOCK=1
    typeset -gx HOMEBREW_NO_EMOJI=1
    typeset -gx HOMEBREW_NO_ENV_HINTS=1
    z::log::debug "Homebrew environment variables configured"
  fi

  if z::probe::cmd "apt"; then
    typeset -gx DEBIAN_FRONTEND=noninteractive
    z::log::debug "APT environment configured"
  fi

  if z::probe::cmd "pacman"; then
    typeset -gx PACMAN_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pacman/pkg"
    if [[ ! -d "$PACMAN_CACHE_DIR" ]]; then
      command mkdir -p -- "$PACMAN_CACHE_DIR" 2>/dev/null \
        && z::log::debug "Created pacman cache directory: $PACMAN_CACHE_DIR" \
        || z::log::warn "Failed to create pacman cache directory: $PACMAN_CACHE_DIR"
    fi
  fi
  return 0
}

# ==============================================================================
# XDG DIRECTORY SETUP
# ==============================================================================

__z::mod::env::setup_xdg() {
  emulate -L zsh -o no_aliases

  if [[ -z "${HOME:-}" ]]; then
    z::log::error "HOME environment variable is not set"
    return 1
  fi

  typeset -gx XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
  typeset -gx XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
  typeset -gx XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
  typeset -gx XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

  z::log::debug "XDG: Config=$XDG_CONFIG_HOME Data=$XDG_DATA_HOME Cache=$XDG_CACHE_HOME State=$XDG_STATE_HOME"
  return 0
}

__z::mod::env::create_xdg_dirs() {
  emulate -L zsh -o no_aliases

  [[ -n "${XDG_CONFIG_HOME:-}" ]] || __z::mod::env::setup_xdg || return 1

  if (( EUID == 0 )); then
    z::log::warn "Running as root, skipping XDG directory permission modifications"
    return 0
  fi

  local -a dirs=(
    "$XDG_CONFIG_HOME:755"
    "$XDG_DATA_HOME:755"
    "$XDG_CACHE_HOME:755"
    "$XDG_STATE_HOME:755"
    "$XDG_CONFIG_HOME/zsh:750"
    "$XDG_CACHE_HOME/zsh:750"
    "$XDG_STATE_HOME/zsh:750"
    "$XDG_CONFIG_HOME/ssh:700"
  )

  local entry dir perm
  for entry in "${dirs[@]}"; do
    dir=${entry%:*}
    perm=${entry#*:}

    if [[ ! -d "$dir" ]]; then
      if command mkdir -p -- "$dir" 2>/dev/null; then
        z::log::debug "Created XDG directory: $dir"
        command chmod "$perm" -- "$dir" 2>/dev/null
      else
        z::log::warn "Failed to create XDG directory: $dir"
      fi
    else
      __z::mod::env::ensure_dir_perms "$dir" "$perm"
    fi
  done

  z::log::debug "XDG directory setup completed"
  return 0
}

# ==============================================================================
# EDITOR SETUP
# ==============================================================================

__z::mod::env::setup_editor() {
  emulate -L zsh -o no_aliases
  local editor_preference

  if   z::probe::cmd "nvim"; then editor_preference=nvim
  elif z::probe::cmd "vim";  then editor_preference=vim
  else                            editor_preference=vi
  fi

  typeset -gx EDITOR="$editor_preference"
  typeset -gx VISUAL="$EDITOR"
  typeset -gx SUDO_EDITOR="$EDITOR"
  typeset -gx GIT_EDITOR="$EDITOR"
  z::log::debug "Editor environment configured: $EDITOR"
  return 0
}

# ==============================================================================
# DEVELOPMENT ENVIRONMENT SETUP
# ==============================================================================

__z::mod::env::_ensure_dir() {
  emulate -L zsh -o no_aliases
  local d=$1
  [[ -d "$d" ]] && return 0
  if command mkdir -p -- "$d" 2>/dev/null; then
    z::log::debug "Created directory: $d"
  else
    z::log::warn "Failed to create directory: $d"
  fi
}

__z::mod::env::setup_development() {
  emulate -L zsh -o no_aliases

  # Go
  if z::probe::cmd "go"; then
    typeset -gx GOPATH="${GOPATH:-$HOME/go}"
    typeset -gx GOBIN="$GOPATH/bin"
    local d
    for d in "$GOPATH" "$GOPATH/src" "$GOPATH/bin" "$GOPATH/pkg"; do
      __z::mod::env::_ensure_dir "$d"
    done
    z::log::debug "Go: GOPATH=$GOPATH"
  fi

  # Rust
  if z::probe::cmd "cargo" || [[ -d "$HOME/.cargo" ]]; then
    typeset -gx CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
    typeset -gx RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
    typeset -gx CARGO_INCREMENTAL=1
    typeset -gx RUST_BACKTRACE=1
    z::log::debug "Rust: CARGO_HOME=$CARGO_HOME"
  fi

  # Node
  if z::probe::cmd "node"; then
    typeset -gx NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-$HOME/.npm-global}"
    __z::mod::env::_ensure_dir "$NPM_CONFIG_PREFIX"
    z::log::debug "Node: NPM_CONFIG_PREFIX=$NPM_CONFIG_PREFIX"
  fi

  # Python
  if z::probe::cmd "python3" || z::probe::cmd "python"; then
    typeset -gx PYTHONDONTWRITEBYTECODE=1
    typeset -gx PYTHONUNBUFFERED=1
    typeset -gx PIP_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pip"
    typeset -gx PIPENV_VENV_IN_PROJECT=1
    __z::mod::env::_ensure_dir "$PIP_CACHE_DIR"
    z::log::debug "Python: PIP_CACHE_DIR=$PIP_CACHE_DIR"
  fi

  # Java / Maven
  if z::probe::cmd "java"; then
    if [[ -z "${JAVA_HOME:-}" ]]; then
      if [[ "$OSTYPE" == darwin* && -x /usr/libexec/java_home ]]; then
        typeset -gx JAVA_HOME="$(/usr/libexec/java_home 2>/dev/null)"
      else
        local jpath
        for jpath in \
          /usr/lib/jvm/default-java \
          /usr/lib/jvm/java-17-openjdk-amd64 \
          /usr/lib/jvm/java-11-openjdk-amd64 \
          /usr/lib/jvm/java-8-openjdk-amd64
        do
          if [[ -d "$jpath" ]]; then
            typeset -gx JAVA_HOME="$jpath"
            break
          fi
        done
      fi
    fi
    : ${MAVEN_OPTS:="-Xmx1024m -XX:MaxMetaspaceSize=256m"}
    typeset -gx MAVEN_OPTS
    typeset -gx M2_HOME="${M2_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/maven}"
    __z::mod::env::_ensure_dir "$M2_HOME"
    z::log::debug "Java: JAVA_HOME=${JAVA_HOME:-Not Found}"
  fi

  # Docker
  if z::probe::cmd "docker"; then
    typeset -gx DOCKER_BUILDKIT=1
    typeset -gx COMPOSE_DOCKER_CLI_BUILD=1
    z::log::debug "Docker environment configured"
  fi

  return 0
}

# ==============================================================================
# XDG COMPLIANCE SETUP
# ==============================================================================

__z::mod::env::setup_xdg_compliance() {
  emulate -L zsh -o no_aliases

  local state=$XDG_STATE_HOME cache=$XDG_CACHE_HOME config=$XDG_CONFIG_HOME

  local -a xdg_app_dirs=(
    "$state/zsh" "$cache/zsh" "$config/zsh"
    "$config/git" "$config/wget" "$config/curl"
    "$config/less" "$state/less"
    "$cache/pip" "$config/maven" "$config/readline"
  )

  local d
  for d in "${xdg_app_dirs[@]}"; do
    [[ -n "$d" ]] && __z::mod::env::_ensure_dir "$d"
  done

  # History file with fallback.
  local hist_dir="${XDG_STATE_HOME}/zsh" hist_file
  if [[ ! -d "$hist_dir" ]]; then
    if command mkdir -p -- "$hist_dir" 2>/dev/null; then
      z::log::debug "Created history directory: $hist_dir"
    else
      hist_dir="$HOME"
      z::log::info "Using fallback history location"
    fi
  fi
  hist_file="$hist_dir/$( [[ "$hist_dir" == "$HOME" ]] && print '.zsh_history' || print 'history' )"

  [[ "$hist_dir" != "$HOME" ]] && __z::mod::env::ensure_dir_perms "$hist_dir" 700

  typeset -gx HISTFILE="$hist_file"

  typeset -gx NODE_REPL_HISTORY="$state/zsh/node_repl_history"
  typeset -gx PYTHON_HISTORY="$state/zsh/python_history"
  typeset -gx PYTHONHISTFILE="$PYTHON_HISTORY"
  typeset -gx SQLITE_HISTORY="$state/zsh/sqlite_history"
  typeset -gx MYSQL_HISTFILE="$state/zsh/mysql_history"
  typeset -gx PSQL_HISTORY="$state/zsh/psql_history"
  typeset -gx REDISCLI_HISTFILE="$state/zsh/redis_history"

  typeset -gx LESSHISTFILE="$state/less/history"
  typeset -gx WGETRC="$config/wget/wgetrc"
  typeset -gx CURL_HOME="$config/curl"
  typeset -gx INPUTRC="$config/readline/inputrc"
  typeset -gx GIT_CONFIG_GLOBAL="$config/git/config"

  z::log::debug "XDG compliance configured"
  return 0
}

# ==============================================================================
# SECURITY SETUP
# ==============================================================================

__z::mod::env::setup_security() {
  emulate -L zsh -o no_aliases

  if z::probe::cmd "gpg" || z::probe::cmd "gpg2"; then
    typeset -gx GNUPGHOME="${XDG_DATA_HOME:-$HOME/.local/share}/gnupg"

    if [[ ! -d "$GNUPGHOME" ]]; then
      if command mkdir -p -m 700 -- "$GNUPGHOME" 2>/dev/null; then
        z::log::debug "Created GPG directory: $GNUPGHOME"
      else
        z::log::warn "Failed to create GPG directory: $GNUPGHOME"
      fi
    else
      __z::mod::env::ensure_dir_perms "$GNUPGHOME" 700
    fi

    if [[ -t 0 && -z "${GPG_TTY:-}" ]]; then
      typeset -gx GPG_TTY="$(command tty 2>/dev/null || print /dev/tty)"
    fi

    z::log::debug "GPG: GNUPGHOME=$GNUPGHOME"
  fi
  return 0
}

# ==============================================================================
# PERFORMANCE SETUP
# ==============================================================================

__z::mod::env::setup_performance() {
  emulate -L zsh -o no_aliases
  if z::probe::cmd "make"; then
    local cores
    cores=$(__z::mod::env::get_cpu_count)
    typeset -gx MAKEFLAGS="-j${cores}"
    z::log::debug "Performance: MAKEFLAGS=$MAKEFLAGS"
  fi
  return 0
}

# ==============================================================================
# TERMINAL SETUP
# ==============================================================================

__z::mod::env::setup_terminal() {
  emulate -L zsh -o no_aliases

  typeset -gx LANG="${LANG:-en_US.UTF-8}"
  typeset -gx LC_ALL="${LC_ALL:-$LANG}"
  typeset -gx TERM="${TERM:-xterm-256color}"
  typeset -gx COLORTERM="${COLORTERM:-truecolor}"

  if z::probe::cmd "less"; then
    typeset -gx PAGER="less"
    typeset -gx LESS="-R -Si -M -j.5"
    if z::probe::cmd "lesspipe.sh"; then
      typeset -gx LESSOPEN="|lesspipe.sh %s"
    elif z::probe::cmd "src-hilite-lesspipe.sh"; then
      typeset -gx LESSOPEN="|src-hilite-lesspipe.sh %s"
      typeset -gx LESSCOLOR=always
    elif z::probe::cmd "pygmentize"; then
      typeset -gx LESSCOLORIZER=pygmentize
    fi
  fi

  typeset -gx LESS_TERMCAP_mb=$'\e[1;32m'
  typeset -gx LESS_TERMCAP_md=$'\e[1;36m'
  typeset -gx LESS_TERMCAP_me=$'\e[0m'
  typeset -gx LESS_TERMCAP_so=$'\e[01;44;33m'
  typeset -gx LESS_TERMCAP_se=$'\e[0m'
  typeset -gx LESS_TERMCAP_us=$'\e[1;4;31m'
  typeset -gx LESS_TERMCAP_ue=$'\e[0m'

  z::log::debug "Terminal: LANG=$LANG TERM=$TERM"
  return 0
}

# ==============================================================================
# CLOUD ENVIRONMENT SETUP
# ==============================================================================

__z::mod::env::setup_cloud() {
  emulate -L zsh -o no_aliases

  if z::probe::cmd "aws"; then
    typeset -gx AWS_CLI_AUTO_PROMPT=on-partial
    typeset -gx AWS_PAGER=""
    z::log::debug "AWS environment configured"
  fi

  if z::probe::cmd "terraform"; then
    local cores
    cores=$(__z::mod::env::get_cpu_count)
    typeset -gx TF_CLI_ARGS_plan="-parallelism=${cores}"
    typeset -gx TF_CLI_ARGS_apply="-parallelism=${cores}"
    z::log::debug "Terraform: parallelism=$cores"
  fi

  if z::probe::cmd "kubectl" && z::probe::cmd "delta"; then
    typeset -gx KUBECTL_EXTERNAL_DIFF="delta --syntax-highlight --paging=never"
    z::log::debug "Kubernetes environment configured"
  fi
  return 0
}

# ==============================================================================
# MODULE INITIALIZATION
# ==============================================================================

__z::mod::env::init() {
  emulate -L zsh -o no_aliases

  z::log::info "Initializing core environment..."
  __z::mod::env::setup_editor          || return $?
  __z::mod::env::setup_package_managers|| return $?
  __z::mod::env::setup_development     || return $?
  __z::mod::env::setup_xdg_compliance  || return $?
  __z::mod::env::setup_security        || return $?
  __z::mod::env::setup_performance     || return $?
  __z::mod::env::setup_terminal        || return $?
  __z::mod::env::setup_cloud           || return $?
  z::log::info "Core environment initialized successfully."
  return 0
}

if z::probe::func "__z::mod::env::init"; then
  __z::mod::env::init
fi
