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
