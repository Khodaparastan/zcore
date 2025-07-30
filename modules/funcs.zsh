extract() {
  local usage="Usage: extract [-d DIR] <archive1> [archive2 ...]\n  -d DIR    Extract to specified directory (default: current directory '.')\n  -h"
  local extract_dir="." opt
  OPTIND=1 # Reset getopts
  while getopts ":d:h" opt; do
    case "$opt" in
    d) extract_dir="$OPTARG" ;;
    h)
      print -r -- "$usage"
      return 0
      ;;
    \?)
      print -u2 "Invalid option: -$OPTARG"
      print -r -u2 -- "$usage"
      return 1
      ;;
    esac
  done
  shift $((OPTIND - 1))

  [[ $# -eq 0 ]] && {
    print -u2 "Error: No archive files specified."
    print -r -u2 -- "$usage"
    return 1
  }
  if [[ "$extract_dir" != "." && ! -d "$extract_dir" ]]; then
    mkdir -p "$extract_dir" || {
      print -u2 "Error: Cannot create directory '$extract_dir'"
      return 1
    }
  fi

  local file success_count=0 failed_count=0
  for file in "$@"; do
    if [[ ! -f "$file" ]]; then
      print -u2 "Error: File not found: $file"
      ((failed_count++))
      continue
    fi

    local abs_extract_dir
    abs_extract_dir="$(cd "$extract_dir" && pwd)" || {
      print -u2 "Error: Invalid extraction directory '$extract_dir'"
      ((failed_count++))
      continue
    }

    print -P "%F{cyan}Extracting: $file to $abs_extract_dir%f"
    local cmd_failed=0
    case "${file:l}" in
    *.tar.bz2 | *.tbz2 | *.tbz) tar xjf "$file" -C "$abs_extract_dir" || cmd_failed=1 ;;
    *.tar.gz | *.tgz) tar xzf "$file" -C "$abs_extract_dir" || cmd_failed=1 ;;
    *.tar.xz | *.txz) tar xJf "$file" -C "$abs_extract_dir" || cmd_failed=1 ;;
    *.tar.lz4)
      if command -v lz4 >/dev/null; then
        lz4 -dc "$file" | tar x -C "$abs_extract_dir" || cmd_failed=1
      else
        print -u2 "Error: lz4 tool needed for $file"
        cmd_failed=1
      fi
      ;;
    *.tar.zst | *.tzst)
      if command -v zstd >/dev/null; then
        zstd -dc "$file" | tar x -C "$abs_extract_dir" || cmd_failed=1
      else
        print -u2 "Error: zstd tool needed for $file"
        cmd_failed=1
      fi
      ;;
    *.tar) tar xf "$file" -C "$abs_extract_dir" || cmd_failed=1 ;;
    *.bz2)
      if command -v bunzip2 >/dev/null; then
        bunzip2 -k "$file" -c >"$abs_extract_dir/${file:t:r}" || cmd_failed=1
      else
        print -u2 "Error: bunzip2 tool needed for $file"
        cmd_failed=1
      fi
      ;;
    *.gz)
      if command -v gunzip >/dev/null; then
        gunzip -k "$file" -c >"$abs_extract_dir/${file:t:r}" || cmd_failed=1
      else
        print -u2 "Error: gunzip tool needed for $file"
        cmd_failed=1
      fi
      ;;
    *.zip | *.jar | *.war | *.ear)
      if command -v unzip >/dev/null; then
        unzip -q "$file" -d "$abs_extract_dir" || cmd_failed=1
      else
        print -u2 "Error: unzip tool needed for $file"
        cmd_failed=1
      fi
      ;;
    *.7z)
      if command -v 7z >/dev/null; then
        7z x "$file" -o"$abs_extract_dir" -y >/dev/null || cmd_failed=1
      else
        print -u2 "Error: 7z tool needed for $file"
        cmd_failed=1
      fi
      ;;
    *.rar)
      if command -v unrar >/dev/null; then
        unrar x -o+ "$file" "$abs_extract_dir/" >/dev/null || cmd_failed=1
      else
        print -u2 "Error: unrar tool needed for $file"
        cmd_failed=1
      fi
      ;;
    *)
      print -u2 "Error: Unsupported archive format: $file"
      cmd_failed=1
      ;;
    esac

    if ((cmd_failed)); then
      print -u2 "Error: Failed to extract $file"
      ((failed_count++))
    else
      print -P "%F{green}Successfully extracted: $file%f"
      ((success_count++))
    fi
  done

  print "Extraction summary: $success_count successful, $failed_count failed."
  return $((failed_count > 0 ? 1 : 0))
}

backup() {
  local usage="Usage: backup [-d DIR] [-c] [-n NAME_PREFIX] <item1> [item2 ...]\n  -d DIR          Specify backup directory (default: $HOME/backups)\n  -c              Compress backup using tar.gz\n  -n NAME_PREFIX  Custom prefix for backup filename\n  -h              Show this help message"
  local backup_dir_base="$HOME/backups" compress_backup=false name_prefix="" opt
  OPTIND=1
  while getopts ":d:cn:h" opt; do
    case "$opt" in
    d) backup_dir_base="$OPTARG" ;;
    c) compress_backup=true ;;
    n) name_prefix="$OPTARG" ;;
    h)
      print -r -- "$usage"
      return 0
      ;;
    \?)
      print -u2 "Invalid option: -$OPTARG"
      print -r -u2 -- "$usage"
      return 1
      ;;
    esac
  done
  shift $((OPTIND - 1))

  [[ $# -eq 0 ]] && {
    print -u2 "Error: No files or directories specified for backup."
    print -r -u2 -- "$usage"
    return 1
  }
  mkdir -p "$backup_dir_base" || {
    print -u2 "Error: Cannot create backup directory: $backup_dir_base"
    return 1
  }

  local timestamp
  timestamp="$(date +%Y%m%d_%H%M%S)" success_count=0 failed_count=0 item
  for item in "$@"; do
    if [[ ! -e "$item" ]]; then
      print -u2 "Error: Item not found: $item"
      ((failed_count++))
      continue
    fi

    local base_name
    base_name="$(basename "$item")"
    local backup_name="${name_prefix:+$name_prefix\_}${base_name}_${timestamp}"
    local backup_path_final="$backup_dir_base/$backup_name"

    print -P "%F{cyan}Backing up: $item%f"
    if $compress_backup; then
      backup_path_final+=".tar.gz"
      if tar czf "$backup_path_final" -C "$(dirname "$item")" "$base_name"; then
        print -P "%F{green}Compressed backup created: $backup_path_final%f"
        ((success_count++))
      else
        print -u2 "Error: Failed to create compressed backup of $item to $backup_path_final"
        ((failed_count++))
      fi
    else
      if cp -a "$item" "$backup_path_final"; then
        print -P "%F{green}Backup created: $backup_path_final%f"
        ((success_count++))
      else
        print -u2 "Error: Failed to backup $item to $backup_path_final"
        ((failed_count++))
      fi
    fi
  done
  print "Backup summary: $success_count successful, $failed_count failed."
  return $((failed_count > 0 ? 1 : 0))
}

sysinfo() {
  print -P "%F{yellow}=== System Information ===%f"
  print "OS: $(uname -s) $(uname -r) ($(uname -o 2>/dev/null || echo 'N/A'))"
  print "Architecture: $(uname -m)"
  print "Hostname: $(hostname -f 2>/dev/null || hostname)"
  print "Shell: Zsh $ZSH_VERSION"
  print "Terminal: $TERM"
  print "Uptime: $(uptime -p 2>/dev/null || uptime | sed -e 's/.*up\\s*//' -e 's/,\\s*[0-9]* users.*//' -e 's/,\\s*load average.*//')"

  if ((IS_MACOS)); then
    print "Model: $(sysctl -n hw.model 2>/dev/null || echo 'N/A')"
    print "CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'N/A') ($(sysctl -n hw.ncpu 2>/dev/null || echo '?') cores)"
    print "Memory: $(($(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1024 / 1024 / 1024)) GB"
    print "macOS Version: $(sw_vers -productName 2>/dev/null || echo 'N/A') $(sw_vers -productVersion 2>/dev/null || echo 'N/A') ($(sw_vers -buildVersion 2>/dev/null || echo 'N/A'))"
  elif ((IS_LINUX)); then
    print "Distribution: $(grep PRETTY_NAME /etc/*release 2>/dev/null | cut -d'\"' -f2 || lsb_release -ds 2>/dev/null || echo 'N/A')"
    print "Kernel: $(uname -r)"
    print "CPU: $(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null || echo 'N/A') ($(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo '?') cores)"
    print "Memory: $(awk '/MemTotal/ {printf "%.2f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 'N/A') GB"
  fi

  print -P "\\n%F{yellow}=== Disk Usage (Root Filesystem) ===%f"
  df -h / 2>/dev/null | tail -n +2

  print -P "\\n%F{yellow}=== Network (Primary IP) ===%f"
  local primary_ip="N/A"
  if command -v ip >/dev/null 2>&1; then
    primary_ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}' || echo "N/A")
  elif command -v ifconfig >/dev/null 2>&1 && command -v netstat >/dev/null 2>&1; then
    local default_iface
    default_iface=$(netstat -rn | grep default | awk '{print $NF}' | head -1)
    [[ -n "$default_iface" ]] && primary_ip=$(ifconfig "$default_iface" 2>/dev/null | grep 'inet ' | awk '{print $2}' || echo "N/A")
  fi
  print "Local IP (Primary): $primary_ip"
  print "External IP: $(curl -s4 ifconfig.me/ip 2>/dev/null || echo 'N/A')"
}

qfind() {
  local usage="Usage: qfind <pattern> [directory] [-type {f|d|l}]\n  Searches for files/directories matching pattern.\n  Default type: all. Default directory: '.' (current).\n  Examples:\n    qfind myFile\n    qfind image.jpg ~/Pictures -type f\n    qfind myProject /opt -type d"
  local pattern search_dir="." type_arg_fd="" type_arg_find=""

  if [[ "$1" == "-h" || "$1" == "--help" || $# -eq 0 ]]; then
    print -r -- "$usage"
    return 0
  fi

  pattern="$1"
  shift

  if [[ "$1" == "-type" && -n "$2" ]]; then
    case "$2" in
    f)
      type_arg_fd="--type f"
      type_arg_find="-type f"
      ;;
    d)
      type_arg_fd="--type d"
      type_arg_find="-type d"
      ;;
    l)
      type_arg_fd="--type l"
      type_arg_find="-type l"
      ;;
    *)
      print -u2 "Invalid type '$2'. Use f (file), d (directory), or l (symlink)."
      return 1
      ;;
    esac
    shift 2
  fi

  [[ -n "$1" ]] && search_dir="$1"

  print -P "%F{cyan}Searching for '$pattern' in '$search_dir'${type_arg_fd:+ ($type_arg_fd)}...%f"
  if command -v fd >/dev/null 2>&1; then
    fd --color=always --hidden --follow --exclude .git ${type_arg_fd:+"$type_arg_fd"} "$pattern" "$search_dir" 2>/dev/null | head -30
  else
    find "$search_dir" ${type_arg_find:+"$type_arg_find"} -iname "*${pattern}*" -print 2>/dev/null | head -30
  fi
}

processes() {
  local usage="Usage: processes [pattern]\n  Shows running processes, optionally filtered by a case-insensitive pattern.\n  Example: processes firefox"
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    print -r -- "$usage"
    return 0
  fi

  if [[ $# -eq 0 ]]; then
    ps aux
  else
    ps aux | grep -iE --color=always "($1|USER.*PID.*COMMAND)" | grep -v grep
  fi
}

memtop() {
  local count="${1:-10}"
  [[ ! "$count" =~ ^[1-9][0-9]*$ || "$count" -lt 1 || "$count" -gt 50 ]] && count=10
  print -P "%F{yellow}Top $count processes by Memory Usage (%MEM):%f"
  if ((IS_MACOS)); then
    ps auxm | head -n $((count + 1))
  else
    ps aux --sort=-%mem | head -n $((count + 1))
  fi
}

cputop() {
  local count="${1:-10}"
  [[ ! "$count" =~ ^[1-9][0-9]*$ || "$count" -lt 1 || "$count" -gt 50 ]] && count=10
  print -P "%F{yellow}Top $count processes by CPU Usage (%CPU):%f"
  if ((IS_MACOS)); then
    ps auxr | head -n $((count + 1))
  else # Linux
    ps aux --sort=-%cpu | head -n $((count + 1))
  fi
}

largest() {
  local dir="${1:-.}" count="${2:-10}"
  [[ ! "$count" =~ ^[1-9][0-9]*$ || "$count" -lt 1 || "$count" -gt 100 ]] && count=10
  if [[ ! -d "$dir" ]]; then
    print -u2 "Error: Directory '$dir' not found."
    return 1
  fi

  print -P "%F{yellow}Largest $count files in '$dir':%f"
  if command -v du >/dev/null 2>&1; then
    du -a "$dir" 2>/dev/null | sort -nr | head -n "$count" | while read -r size file; do
      if [[ -f "$file" ]]; then
        if ((IS_MACOS)); then
          ls -lh "$file" 2>/dev/null
        else
          ls -lh "$file" 2>/dev/null
        fi
      fi
    done
  else
    find "$dir" -type f -exec /bin/ls -lh {} + 2>/dev/null | sort -k5 -hr | head -n "$count"
  fi
}

lowercase() { [[ -n "$1" ]] && print -r -- "${1:l}"; }
uppercase() { [[ -n "$1" ]] && print -r -- "${1:u}"; }

weather() {
  local location="${1:-}"
  if ! command -v curl >/dev/null 2>&1; then
    print -u2 "Error: curl is required for the weather function."
    return 1
  fi
  curl -s "wttr.in/${location}?m&Q&lang=${LANG:-en}" 2>/dev/null || print -u2 "Weather service wttr.in unavailable or query failed for '${location:-your location}'."
}
