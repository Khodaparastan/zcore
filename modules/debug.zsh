z::shell::diagnose_ctrlc() {
  emulate -L zsh
  local log_path
  log_path=$(typeset -f __z::debug::log_path >/dev/null 2>&1 && __z::debug::log_path || print "${ZDOTDIR}/.cursor/debug-b010c6.log")

  print -r -- "=== Ctrl+C Diagnostic ==="
  print -r -- "Log path: $log_path"
  print -r -- "SSH_CONNECTION: ${SSH_CONNECTION:-<none>}"
  print -r -- "SSH_TTY: ${SSH_TTY:-<none>}"
  print -r -- "TERM: ${TERM:-<unset>}"
  print -r -- "KEYMAP: ${KEYMAP:-<unset>}"
  print -r -- "FLOW_CONTROL: $( [[ -o flowcontrol ]] && print on || print off )"
  print -r -- "viins ^C: $(bindkey -M viins '^C' 2>/dev/null)"
  print -r -- "viins CSI-u: $(bindkey -M viins '^[[67;5u' 2>/dev/null)"
  print -r -- "INT trap: $(trap -p INT 2>/dev/null)"
  print -r -- "stty:"
  stty -a </dev/tty 2>/dev/null | rg 'intr|ixon|ixoff|isig|echo' || print "  (no tty)"
  print -r -- ""
  print -r -- "Test 1: At prompt, press Ctrl+C once."
  print -r -- "Test 2: Run: sleep 30  then press Ctrl+C."
  print -r -- "Then inspect: $log_path"
}
z::shell::diagnose_history()
{
  emulate -L zsh

  print -r -- "=== History Configuration Diagnostic ==="
  print -r -- ""
  print -r -- "HISTFILE: ${HISTFILE:-NOT SET}"
  print -r -- "HISTSIZE: ${HISTSIZE:-NOT SET}"
  print -r -- "SAVEHIST: ${SAVEHIST:-NOT SET}"
  print -r -- ""

  if [[ -n "${HISTFILE:-}" ]]; then
    if [[ -f "$HISTFILE" ]]; then
      print -r -- "History file exists: YES"
      print -r -- "Readable: $([[ -r "$HISTFILE" ]] && echo YES || echo NO)"
      print -r -- "Writable: $([[ -w "$HISTFILE" ]] && echo YES || echo NO)"
      print -r -- "Size: $(wc -l < "$HISTFILE" 2>/dev/null || echo "unknown") lines"
      print -r -- "Permissions: $(ls -l "$HISTFILE" | awk '{print $1, $3, $4}')"
    else
      print -r -- "History file exists: NO"
    fi
  fi

  print -r -- ""
  print -r -- "=== History Options ==="
  local opt opt_status
  for opt in APPEND_HISTORY INC_APPEND_HISTORY INC_APPEND_HISTORY_TIME \
             SHARE_HISTORY EXTENDED_HISTORY HIST_IGNORE_SPACE \
             HIST_EXPIRE_DUPS_FIRST HIST_IGNORE_DUPS HIST_FIND_NO_DUPS \
             HIST_REDUCE_BLANKS HIST_SAVE_NO_DUPS; do
    opt_status="OFF"
    [[ -o $opt ]] && opt_status="ON"
    printf "%-30s %s\n" "$opt:" "$opt_status"
  done

  print -r -- ""
  print -r -- "=== History Test ==="
  print -r -- "Attempting to write test entry..."
  if print -r -- "# Test: $(date)" >> "$HISTFILE" 2>&1; then
    print -r -- "✓ Write test successful"
  else
    print -r -- "✗ Write test FAILED"
  fi
}
# Run diagnostic
# z::shell::diagnose_history
