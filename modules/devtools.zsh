#!/usr/bin/env zsh
#
# Development Tools Environment Module
# Configures environments for Go, Rust, Node, Python, Java, Docker, and Cloud tools.
#

# ==============================================================================
# PRIVATE HELPERS
# ==============================================================================

###
# Sets up environments for common programming languages.
###
z::mod::devtools::_setup_languages()
{
  emulate -L zsh
  z::runtime::check_interrupted \
    || return $?

  # --- Go ---
  if z::cmd::exists "go"; then
    typeset -gx GOPATH="${XDG_DATA_HOME}/go"
    typeset -gx GOBIN="$GOPATH/bin"
    [[ ! -d "$GOBIN" ]] \
      && command mkdir -p "$GOBIN" 2> /dev/null
    z::log::debug "Go environment configured"
  fi

  # --- Rust ---
  if z::cmd::exists "cargo"; then
    typeset -gx CARGO_HOME="${XDG_DATA_HOME}/cargo"
    typeset -gx RUSTUP_HOME="${XDG_DATA_HOME}/rustup"
    z::log::debug "Rust environment configured"
  fi

  # --- Node ---
  if z::cmd::exists "node"; then
    typeset -gx NPM_CONFIG_PREFIX="${XDG_DATA_HOME}/npm"
    [[ ! -d "${NPM_CONFIG_PREFIX}/bin" ]] \
      && command mkdir -p "${NPM_CONFIG_PREFIX}/bin" 2> /dev/null
    z::log::debug "Node.js environment configured"
  fi

  # --- Python ---
  if z::cmd::exists "python3"; then
    typeset -gx PYTHONDONTWRITEBYTECODE=1
    typeset -gx PIP_CACHE_DIR="${XDG_CACHE_HOME}/pip"
    [[ ! -d "$PIP_CACHE_DIR" ]] \
      && command mkdir -p "$PIP_CACHE_DIR" 2> /dev/null
    z::log::debug "Python environment configured"
  fi

  # --- Java ---
  if z::cmd::exists "java"; then
    if [[ -z ${JAVA_HOME:-} ]] \
      && ((IS_MACOS)) \
      && [[ -x /usr/libexec/java_home ]]; then
      typeset -gx JAVA_HOME="$(/usr/libexec/java_home 2> /dev/null)"
    fi
    z::log::debug "Java environment configured: JAVA_HOME=${JAVA_HOME:-Not Set}"
  fi
}

###
# Sets up environments for container and cloud tools.
###
z::mod::devtools::_setup_cloud_and_containers()
{
  emulate -L zsh
  z::runtime::check_interrupted \
    || return $?

  # --- Docker ---
  if z::cmd::exists "docker"; then
    typeset -gx DOCKER_BUILDKIT=1
    z::log::debug "Docker environment configured"
  fi

  # --- AWS ---
  if z::cmd::exists "aws"; then
    typeset -gx AWS_PAGER=""
    z::log::debug "AWS environment configured"
  fi

  # --- Terraform ---
  if z::cmd::exists "terraform"; then
    typeset -gx TF_CLI_ARGS_plan="-parallelism=10"
    typeset -gx TF_CLI_ARGS_apply="-parallelism=10"
    z::log::debug "Terraform environment configured"
  fi
}

# ==============================================================================
# MAIN INITIALIZATION
# ==============================================================================
z::mod::devtools::init()
{
  emulate -L zsh
  z::runtime::check_interrupted \
    || return $?
  z::log::info "Initializing development tools environment..."

  z::mod::devtools::_setup_languages
  z::mod::devtools::_setup_cloud_and_containers

  z::log::info "Development tools environment initialized successfully."
}

if z::func::exists "z::mod::devtools::init"; then
  z::mod::devtools::init
fi
