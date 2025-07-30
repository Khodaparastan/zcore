_configure_shell() {
  typeset -grix HISTSIZE=50000
  typeset -grix SAVEHIST=50000

  local hist_file_path="${HISTFILE:-$XDG_STATE_HOME/zsh/history}"
  local hist_dir_to_check

  # Safely extract directory path
  if [[ -n "$hist_file_path" ]]; then
    hist_dir_to_check="${hist_file_path:h}"
  else
    print -u2 -P "%F{yellow}Warning: History file path is empty%f"
    return 1
  fi

  if [[ -n "$hist_dir_to_check" && ! -d "$hist_dir_to_check" ]]; then
    if ! mkdir -p -m 700 "$hist_dir_to_check" 2>/dev/null; then
      print -u2 -P "%F{yellow}Warning: Failed to create history directory: $hist_dir_to_check%f"
    fi
  elif [[ -n "$hist_dir_to_check" && -d "$hist_dir_to_check" ]]; then
    chmod 700 "$hist_dir_to_check" 2>/dev/null
  fi

  setopt EXTENDED_HISTORY
  setopt SHARE_HISTORY
  setopt HIST_EXPIRE_DUPS_FIRST
  setopt HIST_IGNORE_DUPS
  setopt HIST_IGNORE_ALL_DUPS
  setopt HIST_FIND_NO_DUPS
  setopt HIST_SAVE_NO_DUPS
  setopt HIST_REDUCE_BLANKS
  setopt HIST_VERIFY
  setopt INC_APPEND_HISTORY
  setopt APPEND_HISTORY

  setopt AUTO_CD
  setopt AUTO_PUSHD
  setopt PUSHD_IGNORE_DUPS
  setopt AUTO_MENU
  setopt ALWAYS_TO_END
  setopt NO_BEEP
  setopt NO_FLOW_CONTROL
  setopt INTERACTIVE_COMMENTS
  setopt NOTIFY
  setopt LONG_LIST_JOBS
  setopt HASH_LIST_ALL
  setopt NO_CLOBBER
}
