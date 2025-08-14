#!/usr/bin/env zsh
#
# A collection of handy and robust shell helper functions with extra features.
#
# Functions:
#   - extract:   Decompresses/list/tests archives safely with overwrite policy and per-archive dirs.
#   - backup:    Creates timestamped backups with compression choices, excludes, verification, and rotation.
#   - sysinfo:   Displays detailed system, hardware, network, and environment information.
#   - qfind:     Powerful wrapper for fd/find with limits, regex/glob, NUL delim, and per-result exec.
#   - processes: Lists processes with sorting and limiting; optional pattern filter.
#   - memtop:    Lists the top processes by memory usage, optional watch mode.
#   - cputop:    Lists the top processes by CPU usage, optional watch mode.
#   - largest:   Finds the largest files with exclusions and human-readable sizes.
#   - lowercase: Converts input to lowercase (argv or stdin).
#   - uppercase: Converts input to uppercase (argv or stdin).
#   - weather:   Fetches weather from wttr.in with units and 1-line mode.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# SHARED UTILITY HELPERS
# ---------------------------------------------------------------------------

# Check if a command is available in the system's PATH.
# Usage: __have <command>
__have() {
  command -v "$1" >/dev/null 2>&1
}

# Find the first available 7-Zip binary (7z, 7zz, or 7za).
# Prints the binary name to stdout.
__choose_7z() {
  emulate -L zsh
  local b
  for b in 7z 7zz 7za; do
    __have "$b" && {
      print -r -- "$b"
      return 0
    }
  done
  return 1
}


# Generate a unique filesystem path by appending "_N" before the extension
# if the given path already exists. Supports multi-part extensions like ".tar.gz".
# Usage: new_path=$(__unique_path "/path/to/file.txt")
__unique_path() {
  emulate -L zsh
  setopt localoptions warncreateglobal
  local input="$1"
  local dir="${input:h}"
  local base="${input:t}"
  local ext="" tag

  local -a multi_ext=("${__MULTI_EXTS[@]}")

  for tag in "${multi_ext[@]}"; do
    if [[ "$base" == *"$tag" ]]; then
      ext="$tag"
      base="${base%$tag}"
      break
    fi
  done

  if [[ -z "$ext" && "$base" == *.* ]]; then
    ext=".${base##*.}"
    base="${base%$ext}"
  fi

  local candidate="$dir/$base$ext"
  local i=2
  while [[ -e "$candidate" ]]; do
    candidate="$dir/${base}_$i$ext"
    ((i++))
  done
  print -r -- "$candidate"
}

# Return the base filename with common archive extensions stripped.
# Usage: __archive_base_name "foo.tar.gz" -> "foo"
__archive_base_name() {
  emulate -L zsh
  setopt localoptions warncreateglobal
  local name="${1:t}" tag
  local -a multi_ext=("${__MULTI_EXTS[@]}")
  for tag in "${multi_ext[@]}"; do
    if [[ "$name" == *"$tag" ]]; then
      print -r -- "${name%$tag}"
      return 0
    fi
  done
  if [[ "$name" == *.* ]]; then
    print -r -- "${name%.*}"
  else
    print -r -- "$name"
  fi
}

# ---------------------------------------------------------------------------
# MAIN FUNCTIONS
# ---------------------------------------------------------------------------

# Extract a wide variety of archive formats.
# New features:
#   - -l: list archive contents (no extraction)
#   - -t: test archive integrity (no extraction)
#   - -m: create a unique subdir per archive under target dir
#   - -k: keep existing files (skip; no overwrite)
#   - -f: force overwrite existing files
#   - -q / -v: quiet/verbose underlying tool output
extract() {
  emulate -L zsh -o pipefail -o no_aliases
  local CYN="" GRN="" YEL="" RST=""
  if [[ -t 1 && -z "$NO_COLOR" ]]; then
    CYN="\033[36m"
    GRN="\033[32m"
    YEL="\033[33m"
    RST="\033[0m"
  fi



  local extract_dir="." opt do_list=0 do_test=0 make_subdir=0 keep_old=0 force_overwrite=0 verbose=0 quiet=1
  OPTIND=1
  while getopts ":d:ltmkfqhv" opt; do
    case "$opt" in
      d) extract_dir="$OPTARG" ;;
      l) do_list=1 ;;
      t) do_test=1 ;;
      m) make_subdir=1 ;;
      k) keep_old=1 ;;
      f) force_overwrite=1 ;;
      q) quiet=1 ;;
      v) quiet=0; verbose=1 ;;
      h)
        printf "${YEL}Usage:${RST} ${CYN}extract${RST} [${CYN}-d${RST} DIR] [${CYN}-l${RST}|${CYN}-t${RST}] [${CYN}-m${RST}] [${CYN}-k${RST}|${CYN}-f${RST}] [${CYN}-q${RST}|${CYN}-v${RST}] ${GRN}<archive1>${RST} [archive2 ...]\n"
        printf "  Extracts, lists, or tests one or more archives.\n\n"

        printf "${YEL}Options:${RST}\n"
        printf "  ${CYN}-d${RST} DIR    Extract to DIR (default: current directory '.')\n"
        printf "  ${CYN}-l${RST}        List archive contents (no extraction)\n"
        printf "  ${CYN}-t${RST}        Test archive integrity (no extraction)\n"
        printf "  ${CYN}-m${RST}        Make a unique subdirectory per archive inside DIR\n"
        printf "  ${CYN}-k${RST}        Keep existing files (skip overwrite)\n"
        printf "  ${CYN}-f${RST}        Force overwrite existing files\n"
        printf "  ${CYN}-q${RST}        Quiet underlying tool output (default)\n"
        printf "  ${CYN}-v${RST}        Verbose underlying tool output\n"
        printf "  ${CYN}-h${RST}        Show this help message\n\n"

        printf "${YEL}Supported Formats:${RST}\n"
        printf "  ${GRN}Archives:${RST}     .tar, .tar.gz/.tgz, .tar.bz2/.tbz2, .tar.xz/.txz, .tar.zst, .tar.lz4\n"
        printf "  ${GRN}Compressed:${RST}   .zip, .jar, .war, .ear, .7z, .rar\n"
        printf "  ${GRN}Single files:${RST} .gz, .bz2, .xz, .zst, .lz4\n\n"

        printf "${YEL}Examples:${RST}\n"
        printf "  ${CYN}extract${RST} ${GRN}archive.tar.gz${RST}              # Extract to current directory\n"
        printf "  ${CYN}extract${RST} ${CYN}-d${RST} /tmp ${GRN}file.zip${RST}         # Extract to /tmp\n"
        printf "  ${CYN}extract${RST} ${CYN}-l${RST} ${GRN}archive.tar.bz2${RST}       # List contents only\n"
        printf "  ${CYN}extract${RST} ${CYN}-t${RST} ${GRN}backup.7z${RST}            # Test integrity\n"
        printf "  ${CYN}extract${RST} ${CYN}-m${RST} ${GRN}*.tar.gz${RST}            # Extract each to its own subdirectory\n"
        printf "  ${CYN}extract${RST} ${CYN}-f${RST} ${GRN}update.zip${RST}          # Force overwrite existing files\n"
        return 0
        ;;
      \?)
        printf >&2 "Invalid option: -%s\n" "$OPTARG"
        printf >&2 "Use -h for help.\n"
        return 1
        ;;
      :)
        printf >&2 "Option -%s requires an argument\n" "$OPTARG"
        return 1
        ;;
    esac
  done
  shift $((OPTIND - 1))

  if (( do_list + do_test > 1 )); then
    printf >&2 "Error: -l and -t are mutually exclusive.\n"
    return 1
  fi

  if (( keep_old && force_overwrite )); then
    printf >&2 "Error: -k and -f are mutually exclusive.\n"
    return 1
  fi

  (($#)) || {
    printf >&2 "Error: No archive files specified.\n"
    printf >&2 "Use -h for help.\n"
    return 1
  }

  # Create the extraction directory if it doesn't exist.
  if [[ "$extract_dir" != "." && ! -d "$extract_dir" ]]; then
    mkdir -p -- "$extract_dir" || {
      printf >&2 "Error: Cannot create directory '%s'\n" "$extract_dir"
      return 1
    }
  fi

  # Get the absolute path for clear user feedback.
  local abs_extract_dir
  abs_extract_dir="$(cd -- "$extract_dir" 2>/dev/null && pwd -P)" || {
    printf >&2 "Error: Invalid extraction directory '%s'\n" "$extract_dir"
    return 1
  }

  local _7z
  _7z="$(__choose_7z 2>/dev/null || :)"

  local file cmd_failed target dest_dir base_name
  typeset -i success_count=0 failed_count=0

  for file in "$@"; do
    [[ -f "$file" ]] || {
      printf >&2 "Error: File not found: %s\n" "$file"
      ((failed_count++))
      continue
    }

    base_name="$(__archive_base_name "$file")"
    dest_dir="$abs_extract_dir"
    if (( make_subdir )) && (( !do_list && !do_test )); then
      dest_dir="$(__unique_path "$abs_extract_dir/$base_name")"
      mkdir -p -- "$dest_dir" || {
        printf >&2 "Error: Cannot create subdirectory '%s'\n" "$dest_dir"
        ((failed_count++))
        continue
      }
    fi

    ((do_list)) && printf "${CYN}Listing: %s${RST}\n" "$file"
    ((do_test)) && printf "${CYN}Testing: %s${RST}\n" "$file"
    ((!do_list && !do_test)) && printf "${CYN}Extracting: %s → %s${RST}\n" "$file" "$dest_dir"

    cmd_failed=0

    # Overwrite/keep flags per tool
    local tar_keep=() unzip_overwrite=() sz_overwrite=() unrar_overwrite=()
    ((keep_old)) && tar_keep=(-k)
    if ((keep_old)); then
      unzip_overwrite=(-n)
      sz_overwrite=(-aos)   # skip existing
      unrar_overwrite=(-o-) # never overwrite
    elif ((force_overwrite)); then
      unzip_overwrite=(-o)
      sz_overwrite=(-aoa)   # overwrite all
      unrar_overwrite=(-o+) # overwrite all
    else
      unzip_overwrite=(-n)
      sz_overwrite=(-aos)
      unrar_overwrite=(-o-)
    fi

    # Verbosity flags
    local unzip_quiet=() sz_quiet_redirect="/dev/null" unrar_quiet=(-idq) unar_quiet=(-q)
    if ((verbose)); then
      unzip_quiet=()
      sz_quiet_redirect="/dev/stdout"
      unrar_quiet=()
      unar_quiet=()
    elif ((quiet)); then
      unzip_quiet=(-q)
      sz_quiet_redirect="/dev/null"
      unrar_quiet=(-idq)
      unar_quiet=(-q)
    fi

    # Helper for listing and testing single-file compressors
    local single_info
    single_info() {
      local in="$1" ext="${in##*.}"
      case "${ext:l}" in
        gz) printf "Single compressed file → %s (gzip)\n" "${in:t:r}";;
        bz2|bzip2) printf "Single compressed file → %s (bzip2)\n" "${in:t:r}";;
        xz) printf "Single compressed file → %s (xz)\n" "${in:t:r}";;
        zst) printf "Single compressed file → %s (zstd)\n" "${in:t:r}";;
        lz4) printf "Single compressed file → %s (lz4)\n" "${in:t:r}";;
        *) printf "Compressed file → %s\n" "${in:t:r}";;
      esac
    }

    # Use lowercase file extension for matching.
    case "${file:l}" in
    # Tar variants
    *.tar.bz2 | *.tbz2 | *.tbz)
      if ((do_list)); then tar -tjf "$file" || cmd_failed=1
      elif ((do_test)); then tar -tjf "$file" >/dev/null || cmd_failed=1
      else tar -xjf "$file" -C "$dest_dir" "${tar_keep[@]}" || cmd_failed=1
      fi
      ;;
    *.tar.gz | *.tgz)
      if ((do_list)); then tar -tzf "$file" || cmd_failed=1
      elif ((do_test)); then tar -tzf "$file" >/dev/null || cmd_failed=1
      else tar -xzf "$file" -C "$dest_dir" "${tar_keep[@]}" || cmd_failed=1
      fi
      ;;
    *.tar.xz | *.txz)
      if ((do_list)); then tar -tJf "$file" || cmd_failed=1
      elif ((do_test)); then tar -tJf "$file" >/dev/null || cmd_failed=1
      else tar -xJf "$file" -C "$dest_dir" "${tar_keep[@]}" || cmd_failed=1
      fi
      ;;
    *.tar.zst | *.tzst)
      if __have zstd; then
        if ((do_list)); then
          zstd -dc -- "$file" | tar -tf - || cmd_failed=1
        elif ((do_test)); then
          zstd -dc -- "$file" | tar -tf - >/dev/null || cmd_failed=1
        else
          zstd -dc -- "$file" | tar -x -f - -C "$dest_dir" "${tar_keep[@]}" || cmd_failed=1
        fi
      else
        cmd_failed=1
        printf >&2 "Error: 'zstd' is required to process %s\n" "$file"
      fi
      ;;
    *.tar.lz4)
      if __have lz4; then
        if ((do_list)); then
          lz4 -dc -- "$file" | tar -tf - || cmd_failed=1
        elif ((do_test)); then
          lz4 -dc -- "$file" | tar -tf - >/dev/null || cmd_failed=1
        else
          lz4 -dc -- "$file" | tar -x -f - -C "$dest_dir" "${tar_keep[@]}" || cmd_failed=1
        fi
      else
        cmd_failed=1
        printf >&2 "Error: 'lz4' is required to process %s\n" "$file"
      fi
      ;;
    *.tar)
      if ((do_list)); then tar -tf "$file" || cmd_failed=1
      elif ((do_test)); then tar -tf "$file" >/dev/null || cmd_failed=1
      else tar -xf "$file" -C "$dest_dir" "${tar_keep[@]}" || cmd_failed=1
      fi
      ;;

    # Single-file compressors
    *.bz2|*.bzip2)
      if ((do_list)); then single_info "$file"
      elif ((do_test)); then (__have bzip2 && bzip2 -t -- "$file") || (__have bunzip2 && bunzip2 -t -- "$file") || cmd_failed=1
      else
        target=$(__unique_path "$dest_dir/${file:t:r}")
        (__have bunzip2 && bunzip2 -c -- "$file" >|"$target") ||
          (__have bzip2 && bzip2 -dc -- "$file" >|"$target") || {
          cmd_failed=1
          printf >&2 "Error: 'bzip2' or 'bunzip2' required for %s\n" "$file"
        }
      fi
      ;;
    *.gz)
      if ((do_list)); then single_info "$file"
      elif ((do_test)); then (__have gzip && gzip -t -- "$file") || (__have gunzip && gunzip -t -- "$file") || cmd_failed=1
      else
        target=$(__unique_path "$dest_dir/${file:t:r}")
        (__have gunzip && gunzip -c -- "$file" >|"$target") ||
          (__have gzip && gzip -dc -- "$file" >|"$target") || {
          cmd_failed=1
          printf >&2 "Error: 'gzip' or 'gunzip' required for %s\n" "$file"
        }
      fi
      ;;
    *.xz)
      if ((do_list)); then single_info "$file"
      elif ((do_test)); then __have xz && xz -t -- "$file" || cmd_failed=1
      else
        target=$(__unique_path "$dest_dir/${file:t:r}")
        __have xz && xz -dc -- "$file" >|"$target" || {
          cmd_failed=1
          printf >&2 "Error: 'xz' required for %s\n" "$file"
        }
      fi
      ;;
    *.zst)
      if ((do_list)); then single_info "$file"
      elif ((do_test)); then __have zstd && zstd -t -- "$file" || cmd_failed=1
      else
        target=$(__unique_path "$dest_dir/${file:t:r}")
        __have zstd && zstd -dc -- "$file" >|"$target" || {
          cmd_failed=1
          printf >&2 "Error: 'zstd' required for %s\n" "$file"
        }
      fi
      ;;
    *.lz4)
      if ((do_list)); then single_info "$file"
      elif ((do_test)); then __have lz4 && lz4 -t -- "$file" >/dev/null || cmd_failed=1
      else
        target=$(__unique_path "$dest_dir/${file:t:r}")
        __have lz4 && lz4 -dc -- "$file" >|"$target" || {
          cmd_failed=1
          printf >&2 "Error: 'lz4' required for %s\n" "$file"
        }
      fi
      ;;

    # Zip-like
    *.zip | *.jar | *.war | *.ear)
      if ((do_list)); then
        __have unzip && unzip -l "$file" || cmd_failed=1
      elif ((do_test)); then
        __have unzip && unzip -tqq "$file" || cmd_failed=1
      else
        __have unzip && unzip "${unzip_quiet[@]}" "${unzip_overwrite[@]}" -d "$dest_dir" "$file" || {
          cmd_failed=1
          printf >&2 "Error: 'unzip' required for %s\n" "$file"
        }
      fi
      ;;

    # 7z
    *.7z)
      if [[ -n "$_7z" ]]; then
        if ((do_list)); then
          "$_7z" l -- "$file" >$sz_quiet_redirect || cmd_failed=1
        elif ((do_test)); then
          "$_7z" t -y -- "$file" >$sz_quiet_redirect || cmd_failed=1
        else
          "$_7z" x -y "${sz_overwrite[@]}" -o"$dest_dir" -- "$file" >$sz_quiet_redirect || cmd_failed=1
        fi
      else
        cmd_failed=1
        printf >&2 "Error: '7z', '7zz', or '7za' required for %s\n" "$file"
      fi
      ;;

    # RAR
    *.rar)
      if __have unrar; then
        if ((do_list)); then
          unrar l "${unrar_quiet[@]}" -- "$file" >/dev/null || cmd_failed=1
        elif ((do_test)); then
          unrar t "${unrar_quiet[@]}" -- "$file" >/dev/null || cmd_failed=1
        else
          if ((quiet)); then
            unrar x "${unrar_overwrite[@]}" -- "$file" "$dest_dir/" >/dev/null || cmd_failed=1
          else
            unrar x "${unrar_overwrite[@]}" -- "$file" "$dest_dir/" || cmd_failed=1
          fi
        fi
      elif __have unar; then
        if ((do_list)); then
          unar -l "${unar_quiet[@]}" -- "$file" || cmd_failed=1
        else
          local unar_over=()
          ((force_overwrite)) && unar_over=(-f)
          unar "${unar_quiet[@]}" -o "$dest_dir" "${unar_over[@]}" -- "$file" || cmd_failed=1
        fi
      else
        cmd_failed=1
        printf >&2 "Error: 'unrar' or 'unar' required for %s\n" "$file"
      fi
      ;;

    *)
      printf >&2 "Error: Unsupported archive format: %s\n" "$file"
      cmd_failed=1
      ;;
    esac

    if ((cmd_failed)); then
      ((do_list)) || ((do_test)) || printf >&2 "Error: Failed to process %s\n" "$file"
      ((failed_count++))
    else
      if ((do_list)); then
        printf "${GRN}Listed: %s${RST}\n" "$file"
      elif ((do_test)); then
        printf "${GRN}OK: %s (passed integrity test)${RST}\n" "$file"
      else
        printf "${GRN}Successfully extracted: %s${RST}\n" "$file"
      fi
      ((success_count++))
    fi
  done

  local action="Extraction"
  ((do_list)) && action="Listing"
  ((do_test)) && action="Testing"

  printf "\n${YEL}%s Summary:${RST}\n" "$action"
  printf "  ${GRN}Successful: %d${RST}\n" "$success_count"
  printf "  ${failed_count:+\033[31m}Failed: %d${RST}\n" "$failed_count"
  if (( failed_count == 0 )); then
    printf "${GRN}All operations completed successfully!${RST}\n"
  fi
  return $((failed_count > 0))
}
# Create a backup of a file or directory.
# New features:
#   - -z gz|zst|xz      compression format (implies -c)
#   - -L LEVEL          compression level
#   - -e PATTERN        exclude pattern (repeatable, passed to tar --exclude)
#   - -R N              retain only the latest N backups (per item name/prefix)
#   - -V                verify archive after creation
backup() {
  emulate -L zsh -o pipefail -o no_aliases
  local CYN="" GRN="" YEL="" RST=""
  if [[ -t 1 && -z "$NO_COLOR" ]]; then
    CYN="\033[36m"
    GRN="\033[32m"
    YEL="\033[33m"
    RST="\033[0m"
  fi



  local backup_dir_base="${BACKUP_DIR:-$HOME/backups}" name_prefix="" opt
  typeset -i compress_backup=0 retain_n=0 verify_archive=0
  local comp_format="" comp_level=""
  local -a excludes=()

  OPTIND=1
  while getopts ":d:cz:L:e:R:n:Vh" opt; do
    case "$opt" in
      d) backup_dir_base="$OPTARG" ;;
      c) compress_backup=1 ;;
      z)
        comp_format="${OPTARG:l}"
        case "$comp_format" in
          gz|zst|zstd|xz) compress_backup=1 ;;
          *) print -u2 "Error: Invalid compression format '$OPTARG' (use gz|zst|xz)"; return 1 ;;
        esac
        ;;
      L)
        if [[ "$OPTARG" =~ ^[0-9]+$ ]] && (( OPTARG >= 1 && OPTARG <= 22 )); then
          comp_level="$OPTARG"
        else
          print -u2 "Error: Compression level must be a number between 1-22"
          return 1
        fi
        ;;
      e)
        [[ -n "$OPTARG" ]] || { print -u2 "Error: Exclude pattern cannot be empty"; return 1; }
        excludes+=("$OPTARG")
        ;;
      R)
        if [[ "$OPTARG" =~ ^[0-9]+$ ]] && (( OPTARG >= 1 && OPTARG <= 1000 )); then
          retain_n="$OPTARG"
        else
          print -u2 "Error: Retain count must be a number between 1-1000"
          return 1
        fi
        ;;
      n) name_prefix="$OPTARG" ;;
      V) verify_archive=1 ;;
      h)
        printf "${YEL}Usage:${RST} ${CYN}backup${RST} [${CYN}-d${RST} DIR] [${CYN}-c${RST}] [${CYN}-z${RST} FORMAT] [${CYN}-L${RST} LEVEL] [${CYN}-e${RST} PATTERN] [${CYN}-R${RST} N] [${CYN}-n${RST} PREFIX] [${CYN}-V${RST}] ${GRN}<item1>${RST} [item2 ...]\n"
        printf "  Creates a timestamped backup of files or directories.\n\n"

        printf "${YEL}Options:${RST}\n"
        printf "  ${CYN}-d${RST} DIR       Backup directory (default: \$BACKUP_DIR or \$HOME/backups)\n"
        printf "  ${CYN}-c${RST}           Compress the backup (default no; implied by -z)\n"
        printf "  ${CYN}-z${RST} FORMAT    Compression format: ${GRN}gz${RST} | ${GRN}zst${RST} | ${GRN}xz${RST}\n"
        printf "  ${CYN}-L${RST} LEVEL     Compression level (format-dependent, 1-22)\n"
        printf "  ${CYN}-e${RST} PATTERN   Exclude pattern (repeatable; passed to tar --exclude)\n"
        printf "  ${CYN}-R${RST} N         Retain only latest N backups for this item/prefix (rotate)\n"
        printf "  ${CYN}-n${RST} PREFIX    Prepend a custom prefix to the backup filename\n"
        printf "  ${CYN}-V${RST}           Verify archive after creation\n"
        printf "  ${CYN}-h${RST}           Show this help message\n\n"

        printf "${YEL}Environment Variables:${RST}\n"
        printf "  ${GRN}BACKUP_DIR${RST}     Default backup directory location\n\n"

        printf "${YEL}Examples:${RST}\n"
        printf "  ${CYN}backup${RST} ${GRN}myfile.txt${RST}                    # Simple backup\n"
        printf "  ${CYN}backup${RST} ${CYN}-d${RST} /backups ${GRN}project/${RST}       # Backup to specific directory\n"
        printf "  ${CYN}backup${RST} ${CYN}-z${RST} gz ${CYN}-L${RST} 9 ${GRN}largedir/${RST}       # High compression backup\n"
        printf "  ${CYN}backup${RST} ${CYN}-e${RST} '*.log' ${CYN}-e${RST} 'tmp/*' ${GRN}app/${RST}   # Exclude patterns\n"
        printf "  ${CYN}backup${RST} ${CYN}-R${RST} 5 ${CYN}-n${RST} daily ${GRN}docs/${RST}        # Keep 5 backups with prefix\n"
        printf "  ${CYN}backup${RST} ${CYN}-V${RST} ${CYN}-z${RST} zst ${GRN}database.sql${RST}     # Compressed with verification\n"
        return 0
        ;;
      \?)
        printf >&2 "Invalid option: -%s\n" "$OPTARG"
        printf >&2 "Use -h for help.\n"
        return 1
        ;;
      :)
        printf >&2 "Option -%s requires an argument\n" "$OPTARG"
        return 1
        ;;
    esac
  done
  shift $((OPTIND - 1))

  (($#)) || {
    printf >&2 "Error: No files or directories specified for backup.\n"
    printf >&2 "Use -h for help.\n"
    return 1
  }

  mkdir -p -- "$backup_dir_base" || {
    printf >&2 "Error: Cannot create backup directory: %s\n" "$backup_dir_base"
    return 1
  }

  # Validate backup directory is writable
  [[ -w "$backup_dir_base" ]] || {
    printf >&2 "Error: Backup directory is not writable: %s\n" "$backup_dir_base"
    return 1
  }

  local timestamp
  timestamp="$(date +%Y%m%d_%H%M%S)"
  typeset -i success_count=0 failed_count=0

  local item
  for item in "$@"; do
    [[ -e "$item" ]] || {
      printf >&2 "Error: Item not found: %s\n" "$item"
      ((failed_count++))
      continue
    }

    # Normalize path to remove trailing slashes for consistent basename extraction.
    local item_norm="${item%/}"
    local base_name="${item_norm:t}"
    local backup_name="${name_prefix:+${name_prefix}_}${base_name}_${timestamp}"
    local backup_path_final="$backup_dir_base/$backup_name"

    printf "${CYN}Backing up: %s${RST}\n" "$item"

    if ((compress_backup)); then
      # Decide extension and compressor pipeline
      local ext="" comp_cmd=()
      case "$comp_format" in
        ""|"gz")
          ext=".tar.gz"
          if __have pigz; then
            comp_cmd=(pigz)
          else
            comp_cmd=(gzip)
          fi
          [[ -n "$comp_level" ]] && comp_cmd+=(-"$comp_level")
          ;;
        "zst"|"zstd")
          ext=".tar.zst"
          local lvl="${comp_level:-3}"
          if __have zstd; then
            comp_cmd=(zstd -T0 -$lvl -q)
          else
            printf >&2 "Error: 'zstd' not available for zst compression.\n"
            ((failed_count++))
            continue
          fi
          ;;
        "xz")
          ext=".tar.xz"
          if __have xz; then
            comp_cmd=(xz)
          else
            printf >&2 "Error: 'xz' not available for xz compression.\n"
            ((failed_count++))
            continue
          fi
          [[ -n "$comp_level" ]] && comp_cmd+=(-"$comp_level")
          ;;
        *)
          printf >&2 "Error: Unknown compression format '%s' (use gz|zst|xz).\n" "$comp_format"
          ((failed_count++)); continue
          ;;
      esac

      backup_path_final="$(__unique_path "$backup_path_final$ext")"
      local parent="${item_norm:h}"

      # Build tar command with excludes
      local -a tar_args=(-c -f - -C "$parent")
      local ex
      for ex in "${excludes[@]}"; do
        tar_args+=(--exclude "$ex")
      done

      # Create archive via pipe to compressor
      if tar "${tar_args[@]}" -- "$base_name" | "${comp_cmd[@]}" >|"$backup_path_final"; then
        printf "${GRN}Compressed backup created: %s${RST}\n" "$backup_path_final"
        if ((verify_archive)); then
          # Verify by listing contents
          local verify_ok=0
          case "$ext" in
            *.tar.gz)
              if gzip -dc -- "$backup_path_final" | tar -tf - >/dev/null 2>&1; then
                verify_ok=1
              fi
              ;;
            *.tar.zst)
              if zstd -dc -- "$backup_path_final" | tar -tf - >/dev/null 2>&1; then
                verify_ok=1
              fi
              ;;
            *.tar.xz)
              if xz -dc -- "$backup_path_final" | tar -tf - >/dev/null 2>&1; then
                verify_ok=1
              fi
              ;;
          esac
          if ((verify_ok)); then
            printf "${GRN}Verified: %s${RST}\n" "$backup_path_final"
          else
            printf >&2 "Verify failed: %s\n" "$backup_path_final"
            rm -f -- "$backup_path_final" 2>/dev/null
            ((failed_count++))
            continue
          fi
        fi
        ((success_count++))
      else
        printf >&2 "Error: Failed to create compressed backup of %s\n" "$item"
        ((failed_count++))
        continue
      fi
    else
      backup_path_final="$(__unique_path "$backup_path_final")"
      local backup_ok=0

      if __have rsync; then
        # Use rsync
        if [[ -d "$item_norm" ]]; then
          mkdir -p -- "$backup_path_final" && rsync -a -- "$item_norm"/ "$backup_path_final"/ && backup_ok=1
        else
          rsync -a -- "$item_norm" "$backup_path_final" && backup_ok=1
        fi
      else
        # Fallback to cp -pR
        if [[ -d "$item_norm" ]]; then
          mkdir -p -- "$backup_path_final" && cp -pR -- "$item_norm"/ "$backup_path_final"/ && backup_ok=1
        else
          cp -pR -- "$item_norm" "$backup_path_final" && backup_ok=1
        fi
      fi

      if ((backup_ok)); then
        printf "${GRN}Backup created: %s${RST}\n" "$backup_path_final"
        ((success_count++))
      else
        printf >&2 "Error: Failed to backup %s to %s\n" "$item" "$backup_path_final"
        ((failed_count++))
        continue
      fi
    fi

    # Rotation: keep only latest N for this base if requested
    if [[ "$retain_n" =~ ^[0-9]+$ && "$retain_n" -gt 0 ]]; then
      local prefix="${name_prefix:+${name_prefix}_}${base_name}_"
      # Sort newest-first by modification time
      local -a backups to_delete
      backups=("$backup_dir_base"/${prefix}*(N.Om))
      if (( ${#backups[@]} > retain_n )); then
        to_delete=("${backups[@]:$retain_n}")
        if (( ${#to_delete[@]} )); then
          printf "${YEL}Rotating: removing %d old backup(s) for '%s'${RST}\n" "${#to_delete[@]}" "$base_name"
          if rm -rf -- "${to_delete[@]}" 2>/dev/null; then
            printf "${GRN}Successfully removed old backups${RST}\n"
          else
            printf >&2 "${YEL}Warning: Some old backups could not be removed${RST}\n"
          fi
        fi
      fi
    fi
  done

  printf "\n${YEL}Backup Summary:${RST}\n"
  printf "  ${GRN}Successful: %d${RST}\n" "$success_count"
  printf "  ${failed_count:+\033[31m}Failed: %d${RST}\n" "$failed_count"
  if (( failed_count == 0 )); then
    printf "${GRN}All backups completed successfully!${RST}\n"
  fi
  return $((failed_count > 0))
}

# Display system information
sysinfo() {
  emulate -L zsh -o pipefail -o no_aliases
  local CYN="" GRN="" YEL="" RST=""
  if [[ -t 1 && -z "$NO_COLOR" ]]; then
    CYN="\033[36m"
    GRN="\033[32m"
    YEL="\033[33m"
    RST="\033[0m"
  fi

  # Handle help option
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    printf "${YEL}Usage: sysinfo [-h|--help]${RST}\n"
    printf "\n"
    printf "Display comprehensive system information including:\n"
    printf "  - OS and kernel details\n"
    printf "  - Hardware specifications (CPU, Memory, GPU)\n"
    printf "  - Network configuration\n"
    printf "  - Disk usage\n"
    printf "  - Virtualization/container detection\n"
    printf "\n"
    printf "Options:\n"
    printf "  -h, --help    Show this help message\n"
    return 0
  fi

  local os kernel arch host
  os="$(uname -s)"
  kernel="$(uname -r)"
  arch="$(uname -m)"
  host="$(hostname -f 2>/dev/null || hostname)"

  printf "${YEL}=== System Information ===${RST}\n"
  printf "OS: ${CYN}%s${RST} (%s)\n" "$os" "$(uname -o 2>/dev/null || echo 'N/A')"
  printf "Kernel: ${CYN}%s${RST}\n" "$kernel"
  printf "Architecture: ${CYN}%s${RST}\n" "$arch"
  printf "Hostname: ${CYN}%s${RST}\n" "$host"
  printf "Shell: ${CYN}Zsh %s${RST}\n" "$ZSH_VERSION"
  printf "Terminal: ${CYN}%s${RST}\n" "${TERM:-N/A}"

  local proc_count
  proc_count="$( (ps -A 2>/dev/null || ps ax) | tail -n +2 | wc -l | awk '{print $1}' )"
  printf "Processes: ${CYN}%s${RST}\n" "$proc_count"

  local uptime_info load_avg
  uptime_info="$(uptime -p 2>/dev/null || uptime | sed -e 's/.*up[[:space:]]*//' -e 's/,[[:space:]]*[0-9]* users.*//' -e 's/,[[:space:]]*load average.*//')"
  load_avg="$(uptime | awk -F'load average:' '{print $2}' 2>/dev/null | sed 's/^[[:space:]]*//' || echo 'N/A')"
  printf "Uptime: ${CYN}%s${RST}\n" "$uptime_info"
  printf "Load Average: ${CYN}%s${RST}\n" "$load_avg"

  case "$os" in
  Darwin)
    printf "Model: ${CYN}%s${RST}\n" "$(sysctl -n hw.model 2>/dev/null || echo 'N/A')"
    printf "CPU: ${CYN}%s${RST} (%s cores)\n" "$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'N/A')" "$(sysctl -n hw.ncpu 2>/dev/null || echo '?')"
    local mem_bytes mem_gb mem_used
    mem_bytes="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
    mem_gb="$(( mem_bytes / 1024 / 1024 / 1024 ))"
    if command -v vm_stat >/dev/null 2>&1; then
      local pages_free pages_inactive pages_speculative page_size
      pages_free="$(vm_stat | awk '/Pages free:/ {print $3}' | sed 's/\.//')"
      pages_inactive="$(vm_stat | awk '/Pages inactive:/ {print $3}' | sed 's/\.//')"
      pages_speculative="$(vm_stat | awk '/Pages speculative:/ {print $3}' | sed 's/\.//')"
      page_size="$(vm_stat | awk '/page size of/ {print $8}')"
      if [[ -n "$pages_free" && -n "$page_size" ]]; then
        local free_bytes=$(( (pages_free + pages_inactive + pages_speculative) * page_size ))
        local free_gb=$(( free_bytes / 1024 / 1024 / 1024 ))
        local used_gb=$(( mem_gb - free_gb ))
        printf "Memory: ${CYN}%s/%s GB${RST} used\n" "$used_gb" "$mem_gb"
      else
        printf "Memory: ${CYN}%s GB${RST} total\n" "$mem_gb"
      fi
    else
      printf "Memory: ${CYN}%s GB${RST} total\n" "$mem_gb"
    fi
    printf "macOS: ${CYN}%s %s${RST} (%s)\n" "$(sw_vers -productName 2>/dev/null || echo 'N/A')" "$(sw_vers -productVersion 2>/dev/null || echo 'N/A')" "$(sw_vers -buildVersion 2>/dev/null || echo 'N/A')"
    if __have system_profiler; then
      local gpu
      gpu="$(system_profiler SPDisplaysDataType 2>/dev/null | awk -F: '/Chipset Model/ {gsub(/^[ \t]+/,"",$2); print $2; exit}')"
      [[ -n "$gpu" ]] && printf "GPU: ${CYN}%s${RST}\n" "$gpu"
    fi
    ;;
  Linux)
    local distro="N/A"
    if [[ -r /etc/os-release ]]; then
      distro="$(awk -F= '/^PRETTY_NAME=/{gsub(/"/,"",$2); print $2; exit}' /etc/os-release 2>/dev/null)"
    fi
    [[ -z "$distro" || "$distro" == "N/A" ]] && distro="$(lsb_release -ds 2>/dev/null || :)"
    [[ -z "$distro" ]] && distro="N/A"
    printf "Distribution: ${CYN}%s${RST}\n" "$distro"
    printf "CPU: ${CYN}%s${RST} (%s cores)\n" "$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null || echo 'N/A')" "$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo '?')"
    local mem_total mem_available mem_used
    mem_total="$(awk '/^MemTotal:/ {printf "%.0f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0)"
    mem_available="$(awk '/^MemAvailable:/ {printf "%.0f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0)"
    if [[ "$mem_available" -gt 0 && "$mem_total" -gt 0 ]]; then
      mem_used=$(( mem_total - mem_available ))
      printf "Memory: ${CYN}%s/%s GB${RST} used\n" "$mem_used" "$mem_total"
    else
      printf "Memory: ${CYN}%s GB${RST} total\n" "$mem_total"
    fi
    if __have lspci; then
      local gpu
      gpu="$(lspci 2>/dev/null | awk -F': ' '/VGA compatible controller|3D controller|Display controller/ {print $3; exit}')"
      [[ -n "$gpu" ]] && printf "GPU: ${CYN}%s${RST}\n" "$gpu"
    fi
    ;;
  esac

  # Container/virt detection
  if __have systemd-detect-virt; then
    local virt
    virt="$(systemd-detect-virt 2>/dev/null || :)"
    [[ -n "$virt" && "$virt" != "none" ]] && printf "Virtualization: ${CYN}%s${RST}\n" "$virt"
  else
    [[ -f /.dockerenv || -f /run/.containerenv ]] && printf "Container: ${CYN}detected${RST}\n"
  fi

  printf "\n${YEL}=== Disk Usage (Root Filesystem) ===${RST}\n"
  df -h -P / 2>/dev/null | tail -n +2

  printf "\n${YEL}=== Network Information ===${RST}\n"
  local primary_ip="N/A"

  # Try multiple methods to get primary IP
  if __have ip; then
    primary_ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}' || echo "N/A")
  elif [[ "$os" == "Darwin" ]]; then
    # macOS: try multiple approaches
    if __have route && __have ipconfig; then
      local default_iface
      default_iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')
      if [[ -n "$default_iface" ]]; then
        primary_ip=$(ipconfig getifaddr "$default_iface" 2>/dev/null || echo "N/A")
      fi

      # If still N/A, try to find any non-loopback IP
      if [[ "$primary_ip" == "N/A" ]] && __have ifconfig; then
        primary_ip=$(ifconfig 2>/dev/null | awk '/inet / && !/127\.0\.0\.1/ {print $2; exit}' || echo "N/A")
      fi
    fi
  elif __have ifconfig && __have netstat; then
    local default_iface
    default_iface=$(netstat -rn | awk '/^default|^0\.0\.0\.0/ {print $NF; exit}')
    [[ -n "$default_iface" ]] && primary_ip=$(ifconfig "$default_iface" 2>/dev/null | awk '/inet /{print $2; exit}' || echo "N/A")
  fi

  # Last resort: find any non-loopback IP
  if [[ "$primary_ip" == "N/A" ]] && __have ifconfig; then
    primary_ip=$(ifconfig 2>/dev/null | awk '/inet / && !/127\.0\.0\.1/ {print $2; exit}' || echo "N/A")
  fi

  printf "Local IP (Primary): ${CYN}%s${RST}\n" "${primary_ip:-N/A}"

  if __have curl; then
    local ext_ip
    ext_ip="$(curl -fsS4 --connect-timeout 3 --max-time 5 ifconfig.me/ip 2>/dev/null || echo 'Query Failed')"
    printf "External IP: ${CYN}%s${RST}\n" "$ext_ip"
  else
    printf "External IP: ${CYN}N/A${RST} (curl is not installed)\n"
  fi
}

# Quick file search, preferring `fd` but falling back to `find`.
# New features:
#   - -n N         limit results (default: $QFIND_LIMIT or 30)
#   - -0           NUL-delimited output
#   - -r/--regex   treat pattern as regex
#   - -g/--glob    treat pattern as glob (default)
#   - --no-hidden  do not include hidden files
#   - -x CMD ...   execute command per result (use '{}' placeholder)
qfind() {
  emulate -L zsh -o pipefail -o no_aliases
  # color for status (stderr only)
  local CYN="" GRN="" YEL="" RST=""
  if [[ -t 2 && -z "$NO_COLOR" ]]; then
    CYN="\033[36m"; GRN="\033[32m"; YEL="\033[33m"; RST="\033[0m"
  fi

  if [[ "$1" == "-h" || "$1" == "--help" || $# -eq 0 ]]; then
    printf "${YEL}Usage:${RST} ${CYN}qfind${RST} ${GRN}<pattern>${RST} [directory] [options]\n"
    printf "  Fast file search wrapper around fd(1) or find(1).\n\n"

    printf "${YEL}Arguments:${RST}\n"
    printf "  ${GRN}pattern${RST}       Search pattern (glob by default; quote to prevent shell expansion).\n"
    printf "                  In glob mode, pattern is wrapped in *pattern* unless already wildcarded.\n"
    printf "  ${GRN}directory${RST}     Directory to search (default: '.').\n\n"

    printf "${YEL}Options:${RST}\n"
    printf "  ${CYN}-type${RST} <t>     Filter by type: 'f' (file), 'd' (directory), 'l' (symlink).\n"
    printf "  ${CYN}-n${RST} N          Limit to first N results (default: \$QFIND_LIMIT or 30)\n"
    printf "  ${CYN}-0${RST}            NUL-delimited output\n"
    printf "  ${CYN}-r${RST}, ${CYN}--regex${RST}   Use regex mode\n"
    printf "  ${CYN}-g${RST}, ${CYN}--glob${RST}    Use glob mode (default)\n"
    printf "  ${CYN}--no-hidden${RST}   Do not include hidden files/directories\n"
    printf "  ${CYN}--exact${RST}       Use exact pattern matching (no automatic wildcards)\n"
    printf "  ${CYN}-x${RST} CMD ...    Execute CMD per result; '{}' expands to the path (consumes remaining args)\n"
    printf "  ${CYN}-h${RST}, ${CYN}--help${RST}    Show this help message.\n"
    printf "  ${CYN}-v${RST}, ${CYN}--verbose${RST} Show which backend (fd/find) is being used.\n\n"

    printf "${YEL}Examples:${RST}\n"
    printf "  ${CYN}qfind${RST} ${GRN}myFile${RST}                    # finds *myFile*\n"
    printf "  ${CYN}qfind${RST} ${GRN}'*.iso'${RST} -type f -n 100    # finds *.iso files\n"
    printf "  ${CYN}qfind${RST} --exact ${GRN}README.md${RST}         # finds exactly README.md\n"
    printf "  ${CYN}qfind${RST} ${GRN}src${RST} . -type f -x wc -l    # count lines in files matching *src*\n"
    return 0
  fi

  local pattern="$1"; shift
  local search_dir="." type_letter="" mode="glob" no_hidden=0 zero_delim=0
  local limit="${QFIND_LIMIT:-30}" exact=0 verbose=0
  local -a exec_cmd=()

  # Parse remaining args: directory and options
  while (($#)); do
    case "$1" in
      -type)
        [[ -n "$2" ]] || { print -u2 "Missing argument for -type"; return 1; }
        case "$2" in f|d|l) type_letter="$2" ;; *) print -u2 "Invalid type '$2'"; return 1 ;; esac
        shift 2
        ;;
      -n)
        [[ -n "$2" ]] || { print -u2 "Missing value for -n"; return 1; }
        limit="$2"; shift 2
        ;;
      -0) zero_delim=1; shift ;;
      -r|--regex) mode="regex"; shift ;;
      -g|--glob)  mode="glob"; shift ;;
      --no-hidden) no_hidden=1; shift ;;
      --exact) exact=1; shift ;;
      -v|--verbose) verbose=1; shift ;;
      -x)
        shift
        (( $# )) || { print -u2 "Error: -x requires a command"; return 1; }
        exec_cmd=("$@"); shift $#
        ;;
      -h|--help)
        print -r -- "$usage"; return 0
        ;;
      -*)
        print -u2 "Unknown option: $1"; return 1
        ;;
      *)
        if [[ "$search_dir" == "." ]]; then search_dir="$1"; shift
        else print -u2 "Unexpected argument: $1"; return 1
        fi
        ;;
    esac
  done

  # Validate limit
  if [[ ! "$limit" =~ ^[0-9]+$ || "$limit" -lt 1 ]]; then
    limit=30
  fi

  [[ -d "$search_dir" ]] || { printf >&2 "Error: Directory '%s' not found.\n" "$search_dir"; return 1; }

  # Detect available backend
  local backend="none"
  if __have fd; then
    backend="fd"
  elif command -v find >/dev/null 2>&1; then
    backend="find"
  else
    printf >&2 "Error: Neither 'fd' nor 'find' command is available.\n"
    return 1
  fi

  # Status line (stderr)
  if (( !zero_delim )) && [[ -t 2 ]]; then
    printf >&2 "${CYN}Searching for '%s' in '%s'%s%s%s${RST}\n" \
      "$pattern" "$search_dir" \
      "${type_letter:+ (type: $type_letter)}" \
      "${verbose:+ using $backend}" \
      "..."
  fi

  # Decide color behavior for fd:
  # - auto by default (fd disables color when piped)
  # - never when executing commands (-x) or using NUL (-0)
  local fd_color="auto"
  if (( zero_delim || ${#exec_cmd[@]} )); then
    fd_color="never"
  fi

  # Build producer (fd preferred, find fallback)
  local -a prod_cmd
  if [[ "$backend" == "fd" ]]; then
    local -a fd_type_args=()
    [[ "$type_letter" == "f" ]] && fd_type_args+=(--type f)
    [[ "$type_letter" == "d" ]] && fd_type_args+=(--type d)
    [[ "$type_letter" == "l" ]] && fd_type_args+=(--type l)

    prod_cmd=(fd --color="$fd_color" --follow "${fd_type_args[@]}")
    ((no_hidden)) || prod_cmd+=(--hidden)

    local search_pattern="$pattern"
    if [[ "$mode" == "regex" ]]; then
      prod_cmd+=(--regex -- "$search_pattern" "$search_dir")
    else
      # Auto-wrap pattern unless exact mode or already contains wildcards
      if (( !exact )) && [[ "$search_pattern" != *'*'* && "$search_pattern" != *'?'* ]]; then
        search_pattern="*${search_pattern}*"
      fi
      prod_cmd+=(--glob -- "$search_pattern" "$search_dir")
    fi
    ((zero_delim)) && prod_cmd+=(-0)
  else
    prod_cmd=(find "$search_dir")
    if ((no_hidden)); then
      # prune hidden dirs and skip hidden files
      prod_cmd+=( \( -path "*/.*" -prune \) -o )
    fi
    [[ -n "$type_letter" ]] && prod_cmd+=(-type "$type_letter")

    local search_pattern="$pattern"
    if [[ "$mode" == "regex" ]]; then
      prod_cmd+=(-iregex ".*${search_pattern}.*")
    else
      # Auto-wrap pattern unless exact mode or already contains wildcards
      if (( !exact )) && [[ "$search_pattern" != *'*'* && "$search_pattern" != *'?'* ]]; then
        search_pattern="*${search_pattern}*"
      fi
      prod_cmd+=(-iname "$search_pattern")
    fi
    ((zero_delim)) && prod_cmd+=(-print0) || prod_cmd+=(-print)
  fi

  # '{}' substitution helper
  local _run_exec
  _run_exec() {
    local p="$1"
    local -a out=()
    local replaced=0 x
    for x in "${exec_cmd[@]}"; do
      if [[ "$x" == '{}' ]]; then
        out+=("$p"); replaced=1
      else
        out+=("$x")
      fi
    done
    ((replaced)) || out+=("$p")
    "${out[@]}"
  }

  # Stream results, enforce limit, run -x if provided
  typeset -i count=0
  if ((zero_delim)); then
    "${prod_cmd[@]}" 2>/dev/null | while IFS= read -r -d $'\0' p; do
      (( ++count > limit )) && break
      if (( ${#exec_cmd[@]} )); then
        _run_exec "$p"
      else
        printf '%s\0' "$p"
      fi
    done
  else
    "${prod_cmd[@]}" 2>/dev/null | while IFS= read -r p; do
      (( ++count > limit )) && break
      if (( ${#exec_cmd[@]} )); then
        _run_exec "$p"
      else
        printf '%s\n' "$p"
      fi
    done
  fi
}


# ---------------------------------------------------------------------------
# SIMPLE WRAPPERS
# ---------------------------------------------------------------------------

# List running processes, with sorting and optional filter.
#   processes [-s cpu|mem] [-n N] [pattern]
processes() {
  emulate -L zsh -o pipefail -o no_aliases
  local usage="Usage: processes [-s cpu|mem] [-n N] [pattern]
  Shows running processes, optionally filtered and sorted.
  Example: processes -s cpu -n 20 firefox"

  local sort_key="" count=0 opt
  OPTIND=1
  while getopts ":s:n:h" opt; do
    case "$opt" in
      s) sort_key="$OPTARG" ;;
      n) count="$OPTARG" ;;
      h) print -r -- "$usage"; return 0 ;;
      \?) print -u2 "Invalid option: -$OPTARG"; print -r -u2 -- "$usage"; return 1 ;;
    esac
  done
  shift $((OPTIND - 1))

  local pattern="$1"

  local os; os="$(uname -s)"
  if [[ "$os" == "Darwin" ]]; then
    {
      ps aux | head -n 1
      local body
      body="$(LC_ALL=C ps aux | tail -n +2)"
      case "$sort_key" in
        cpu) print -r -- "$body" | sort -nrk 3,3 ;;
        mem) print -r -- "$body" | sort -nrk 4,4 ;;
        *)   print -r -- "$body" ;;
      esac
    } | {
      if [[ -n "$pattern" ]]; then
        awk -v pat="$pattern" 'BEGIN{IGNORECASE=1} NR==1 || index($0, pat)'
      else
        cat
      fi
    } | {
      if [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]]; then
        head -n $((count + 1))
      else
        cat
      fi
    }
  else
    local -a args=(ps aux)
    case "$sort_key" in
      cpu) args+=(--sort=-%cpu) ;;
      mem) args+=(--sort=-%mem) ;;
    esac
    "${args[@]}" | {
      if [[ -n "$pattern" ]]; then
        awk -v pat="$pattern" 'BEGIN{IGNORECASE=1} NR==1 || index($0, pat)'
      else
        cat
      fi
    } | {
      if [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]]; then
        head -n $((count + 1))
      else
        cat
      fi
    }
  fi
}

# List top processes by memory usage.
#   memtop [N] [-w seconds]
memtop() {
  emulate -L zsh -o pipefail -o no_aliases
  local CYN="" GRN="" YEL="" RST=""
  if [[ -t 1 && -z "$NO_COLOR" ]]; then
    CYN="\033[36m"
    GRN="\033[32m"
    YEL="\033[33m"
    RST="\033[0m"
  fi

  local count=10 interval=0 opt

  # If first arg is a number, treat as count
  if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
    count="$1"; shift
  fi

  OPTIND=1
  while getopts ":w:h" opt; do
    case "$opt" in
      w)
        if [[ "$OPTARG" =~ ^[0-9]+(\.[0-9]+)?$ ]] && (( $(echo "$OPTARG > 0" | awk '{if($1>0) print 1; else print 0}') )); then
          interval="$OPTARG"
        else
          print -u2 "Error: Invalid interval '$OPTARG'. Must be a positive number."
          return 1
        fi
        ;;
      h)
        print "Usage: memtop [N] [-w seconds] [-h]"
        print ""
        print "Show top processes by memory usage."
        print ""
        print "Arguments:"
        print "  N          Number of processes to show (1-50, default: 10)"
        print ""
        print "Options:"
        print "  -w seconds Watch mode - refresh every N seconds"
        print "  -h         Show this help message"
        return 0
        ;;
      \?) print -u2 "Invalid option: -$OPTARG"; return 1 ;;
    esac
  done
  shift $((OPTIND - 1))

  # If trailing arg is a number, also allow it as count
  if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
    count="$1"; shift
  fi

  if [[ ! "$count" =~ ^[0-9]+$ ]] || ((count < 1 || count > 50)); then
    count=10
  fi

  local run_once
  run_once() {
    printf "${YEL}Top $count processes by Memory Usage (%%MEM):${RST}\n"
    local ps_output

    if [[ "$(uname -s)" == "Darwin" ]]; then
      ps_output=$(LC_ALL=C ps aux 2>/dev/null)
      if [[ $? -ne 0 || -z "$ps_output" ]]; then
        printf >&2 "Error: ps command failed\n"
        return 1
      fi

      # Print header in green
      printf "${GRN}%s${RST}\n" "$(echo "$ps_output" | head -n 1)"

      # Sort and display top processes with MEM highlighting
      echo "$ps_output" | tail -n +2 | sort -nrk 4,4 | head -n "$count" | \
        awk -v cyn="${CYN}" -v rst="${RST}" '{
          # Highlight MEM percentage (4th column)
          $4 = cyn $4 rst
          print
        }'
    else
      ps_output=$(LC_ALL=C ps aux --sort=-%mem 2>/dev/null | head -n $((count + 1)))
      if [[ $? -ne 0 || -z "$ps_output" ]]; then
        printf >&2 "Error: ps command failed\n"
        return 1
      fi

      # Print header in green, highlight MEM column in cyan
      echo "$ps_output" | awk -v grn="${GRN}" -v cyn="${CYN}" -v rst="${RST}" '
        NR==1 {
          print grn $0 rst
          next
        }
        {
          # Highlight MEM percentage (4th column)
          $4 = cyn $4 rst
          print
        }'
    fi
    return 0
  }

  if (( interval > 0 )); then
    if __have watch; then
      # Use watch
      if [[ "$(uname -s)" == "Darwin" ]]; then
        watch -n "$interval" "ps aux | head -n 1; LC_ALL=C ps aux | tail -n +2 | sort -nrk 4,4 | head -n $count"
      else
        watch -n "$interval" "ps aux --sort=-%mem | head -n $((count + 1))"
      fi
    else
      # Fallback to manual loop
      while :; do
        clear 2>/dev/null || printf '\033[H\033[2J'  # Clear screen
        run_once
        local exit_code=$?
        if [[ $exit_code -ne 0 ]]; then
          printf >&2 "Error running ps command (exit code: $exit_code), exiting...\n"
          break
        fi
        sleep "$interval" || break
      done
    fi
  else
    run_once
  fi
}

# List top processes by CPU usage.
#   cputop [N] [-w seconds]
cputop() {
  emulate -L zsh -o pipefail -o no_aliases
  local CYN="" GRN="" YEL="" RST=""
  if [[ -t 1 && -z "$NO_COLOR" ]]; then
    CYN="\033[36m"
    GRN="\033[32m"
    YEL="\033[33m"
    RST="\033[0m"
  fi

  local count=10 interval=0 opt

  # If first arg is a number, treat as count
  if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
    count="$1"; shift
  fi

  OPTIND=1
  while getopts ":w:h" opt; do
    case "$opt" in
      w)
        if [[ "$OPTARG" =~ ^[0-9]+(\.[0-9]+)?$ ]] && (( $(echo "$OPTARG > 0" | awk '{if($1>0) print 1; else print 0}') )); then
          interval="$OPTARG"
        else
          print -u2 "Error: Invalid interval '$OPTARG'. Must be a positive number."
          return 1
        fi
        ;;
      h)
        print "Usage: cputop [N] [-w seconds] [-h]"
        print ""
        print "Show top processes by CPU usage."
        print ""
        print "Arguments:"
        print "  N          Number of processes to show (1-50, default: 10)"
        print ""
        print "Options:"
        print "  -w seconds Watch mode - refresh every N seconds"
        print "  -h         Show this help message"
        return 0
        ;;
      \?) print -u2 "Invalid option: -$OPTARG"; return 1 ;;
    esac
  done
  shift $((OPTIND - 1))

  # Trailing numeric count accepted
  if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
    count="$1"; shift
  fi

  if [[ ! "$count" =~ ^[0-9]+$ ]] || ((count < 1 || count > 50)); then
    count=10
  fi

  local run_once
  run_once() {
    printf "${YEL}Top $count processes by CPU Usage (%%CPU):${RST}\n"
    local ps_output

    if [[ "$(uname -s)" == "Darwin" ]]; then
      ps_output=$(LC_ALL=C ps aux 2>/dev/null)
      if [[ $? -ne 0 || -z "$ps_output" ]]; then
        printf >&2 "Error: ps command failed\n"
        return 1
      fi

      # Print header in green
      printf "${GRN}%s${RST}\n" "$(echo "$ps_output" | head -n 1)"

      # Sort and display top processes with CPU highlighting
      echo "$ps_output" | tail -n +2 | sort -nrk 3,3 | head -n "$count" | \
        awk -v cyn="${CYN}" -v rst="${RST}" '{
          # Highlight CPU percentage (3rd column)
          $3 = cyn $3 rst
          print
        }'
    else
      ps_output=$(LC_ALL=C ps aux --sort=-%cpu 2>/dev/null | head -n $((count + 1)))
      if [[ $? -ne 0 || -z "$ps_output" ]]; then
        printf >&2 "Error: ps command failed\n"
        return 1
      fi

      # Print header in green, highlight CPU column in cyan
      echo "$ps_output" | awk -v grn="${GRN}" -v cyn="${CYN}" -v rst="${RST}" '
        NR==1 {
          print grn $0 rst
          next
        }
        {
          # Highlight CPU percentage (3rd column)
          $3 = cyn $3 rst
          print
        }'
    fi
    return 0
  }

  if (( interval > 0 )); then
    if __have watch; then
      # Use watch
      if [[ "$(uname -s)" == "Darwin" ]]; then
        watch -n "$interval" "ps aux | head -n 1; LC_ALL=C ps aux | tail -n +2 | sort -nrk 3,3 | head -n $count"
      else
        watch -n "$interval" "ps aux --sort=-%cpu | head -n $((count + 1))"
      fi
    else
      # Fallback to manual loop
      while :; do
        clear 2>/dev/null || printf '\033[H\033[2J'  # Clear screen
        run_once
        local exit_code=$?
        if [[ $exit_code -ne 0 ]]; then
          printf >&2 "Error running ps command (exit code: $exit_code), exiting...\n"
          break
        fi
        sleep "$interval" || break
      done
    fi
  else
    run_once
  fi
}

# Find the largest files in a given directory.
# New features:
#   - -H            human-readable sizes
#   - -x PATTERN    exclude pattern (repeatable; pruned by find)
#   - -f            follow symlinks
largest() {
  emulate -L zsh -o pipefail -o no_aliases

  # Color setup
  local CYN="" GRN="" YEL="" RST="" RED=""
  if [[ -t 1 && -z "$NO_COLOR" ]]; then
    CYN="%F{cyan}"; GRN="%F{green}"; YEL="%F{yellow}"; RST="%f"; RED="%F{red}"
  fi

  # Default values
  local dir="." count=10 human=0 follow=0 debug=0 opt
  local -a excludes=()

  # Parse options
  while getopts ":x:Hd:fhv" opt; do
    case "$opt" in
      d) dir="$OPTARG" ;;
      H) human=1 ;;
      f) follow=1 ;;
      v) debug=1 ;;
      x)
        if [[ -n "$OPTARG" ]]; then
          excludes+=("$OPTARG")
        else
          print -u2 "${RED}Error: Empty exclude pattern not allowed${RST}"
          return 1
        fi
        ;;
      h)
        print "Usage: largest [-d DIR] [-H] [-f] [-v] [-x PATTERN ...] [count]"
        print ""
        print "Find the largest files in a directory tree."
        print ""
        print "Options:"
        print "  -d DIR     Directory to search (default: current directory)"
        print "  -H         Display file sizes in human-readable format"
        print "  -f         Follow symbolic links during traversal"
        print "  -v         Verbose/debug mode - show diagnostic information"
        print "  -x PATTERN Exclude files matching shell glob pattern (repeatable)"
        print "  -h         Show this help message"
        print ""
        print "Arguments:"
        print "  count      Number of largest files to display (1-100, default: 10)"
        return 0
        ;;
      :) print -u2 "${RED}Error: Option -$OPTARG requires an argument${RST}"; return 1 ;;
      \?) print -u2 "${RED}Error: Invalid option -$OPTARG. Use -h for help.${RST}"; return 1 ;;
    esac
  done
  shift $((OPTIND - 1))

  # Validate count parameter
  if [[ -n "$1" ]]; then
    if [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 100 )); then
      count="$1"
    else
      print -u2 "${RED}Error: Count must be a positive integer between 1 and 100${RST}"
      return 1
    fi
  fi

  # Validate directory
  if [[ ! -d "$dir" ]]; then
    print -u2 "${RED}Error: Directory '$dir' does not exist or is not accessible${RST}"
    return 1
  fi

  print -P "${YEL}Searching for largest $count files in '${CYN}$dir${YEL}':${RST}"

  # Build find command
  local -a find_cmd
  if (( follow )); then
    find_cmd=(find -L "$dir")
    (( debug )) && print -P "${CYN}Debug: Following symbolic links${RST}" >&2
  else
    find_cmd=(find "$dir")
  fi

  # Add exclusions
  if (( ${#excludes[@]} > 0 )); then
    (( debug )) && print -P "${CYN}Debug: Excluding patterns: ${excludes[*]}${RST}" >&2
    find_cmd+=(\( -false)
    local ex
    for ex in "${excludes[@]}"; do
      find_cmd+=(-o -name "$ex")
    done
    find_cmd+=(\) -prune -o -type f -print0)
  else
    find_cmd+=(-type f -print0)
  fi

  # Detect stat command type - GNU vs BSD
  local stat_type
  if stat --version >/dev/null 2>&1; then
    stat_type="gnu"
  else
    stat_type="bsd"
  fi

  # Validate parallel jobs setting
  local jobs="${LARGEST_JOBS:-4}"
  if [[ ! "$jobs" =~ ^[0-9]+$ ]] || (( jobs < 1 || jobs > 16 )); then
    jobs=4
  fi
  (( debug )) && print -P "${CYN}Debug: Using $jobs parallel jobs${RST}" >&2

  # Show commands if debug mode
  if (( debug )); then
    print -P "${CYN}Debug: Find command: ${find_cmd[*]}${RST}" >&2
    print -P "${CYN}Debug: Stat type: $stat_type${RST}" >&2
  fi

  # Execute pipeline with stat command construction
  local error_output
  error_output=$(mktemp)

  if [[ "$stat_type" == "gnu" ]]; then
    # GNU stat version (Linux and GNU coreutils on macOS)
    LC_ALL=C "${find_cmd[@]}" 2>"$error_output" | \
      xargs -0 -n 64 -P "$jobs" stat -c "%s	%N" -- 2>>"$error_output" | \
      awk -v k="$count" -v human="$human" -v debug="$debug" -F $'\t' '
        function humanize(bytes,    units, i, size) {
          if (bytes <= 0) return "0 B"
          split("B KB MB GB TB PB", units, " ")
          size = bytes
          i = 1
          while (size >= 1024 && i < 6) {
            size /= 1024
            i++
          }
          return sprintf("%.1f %s", size, units[i])
        }

        function clean_path(str) {
          # GNU %N adds quotes around filenames with special characters
          if (str ~ /^".*"$/) {
            gsub(/^"|"$/, "", str)
            gsub(/\\"/, "\"", str)  # Unescape quotes
          }
          return str
        }

        BEGIN {
          if (debug) print "Debug: AWK processing started (GNU)" > "/dev/stderr"
        }

        {
          file_size = $1 + 0
          file_path = clean_path($2)

          # Skip invalid entries
          if (file_size <= 0 || file_path == "") {
            if (debug) printf "Debug: Skipping invalid entry: size=%s, path=%s\n", $1, $2 > "/dev/stderr"
            next
          }

          processed++
          if (debug && processed % 1000 == 0) {
            printf "Debug: Processed %d files\n", processed > "/dev/stderr"
          }

          if (num_files < k) {
            num_files++
            sizes[num_files] = file_size
            paths[num_files] = file_path
          } else {
            # Find minimum in our top-k array
            min_idx = 1
            for (i = 2; i <= num_files; i++) {
              if (sizes[i] < sizes[min_idx]) min_idx = i
            }
            if (file_size > sizes[min_idx]) {
              sizes[min_idx] = file_size
              paths[min_idx] = file_path
            }
          }
        }

        END {
          if (debug) printf "Debug: Processed %d total files, found %d largest\n", processed, num_files > "/dev/stderr"

          if (num_files == 0) {
            print "No files found matching criteria" > "/dev/stderr"
            exit 1
          }

          # Sort descending
          for (i = 1; i <= num_files; i++) {
            max_idx = i
            for (j = i + 1; j <= num_files; j++) {
              if (sizes[j] > sizes[max_idx]) max_idx = j
            }
            if (max_idx != i) {
              temp = sizes[i]; sizes[i] = sizes[max_idx]; sizes[max_idx] = temp
              temp = paths[i]; paths[i] = paths[max_idx]; paths[max_idx] = temp
            }
          }

          # Output results with colors
          for (i = 1; i <= num_files; i++) {
            if (human) {
              printf "\033[32m%10s\033[0m  %s\n", humanize(sizes[i]), paths[i]
            } else {
              printf "\033[32m%12d\033[0m  %s\n", sizes[i], paths[i]
            }
          }
        }
      '
  else
    # BSD stat version (macOS native stat)
    LC_ALL=C "${find_cmd[@]}" 2>"$error_output" | \
      xargs -0 -n 64 -P "$jobs" stat -f "%z	%n" 2>>"$error_output" | \
      awk -v k="$count" -v human="$human" -v debug="$debug" -F $'\t' '
        function humanize(bytes,    units, i, size) {
          if (bytes <= 0) return "0 B"
          split("B KB MB GB TB PB", units, " ")
          size = bytes
          i = 1
          while (size >= 1024 && i < 6) {
            size /= 1024
            i++
          }
          return sprintf("%.1f %s", size, units[i])
        }

        BEGIN {
          if (debug) print "Debug: AWK processing started (BSD)" > "/dev/stderr"
        }

        {
          file_size = $1 + 0
          file_path = $2

          # Skip invalid entries
          if (file_size <= 0 || file_path == "") {
            if (debug) printf "Debug: Skipping invalid entry: size=%s, path=%s\n", $1, $2 > "/dev/stderr"
            next
          }

          processed++
          if (debug && processed % 1000 == 0) {
            printf "Debug: Processed %d files\n", processed > "/dev/stderr"
          }

          if (num_files < k) {
            num_files++
            sizes[num_files] = file_size
            paths[num_files] = file_path
          } else {
            # Find minimum in our top-k array
            min_idx = 1
            for (i = 2; i <= num_files; i++) {
              if (sizes[i] < sizes[min_idx]) min_idx = i
            }
            if (file_size > sizes[min_idx]) {
              sizes[min_idx] = file_size
              paths[min_idx] = file_path
            }
          }
        }

        END {
          if (debug) printf "Debug: Processed %d total files, found %d largest\n", processed, num_files > "/dev/stderr"

          if (num_files == 0) {
            print "No files found matching criteria" > "/dev/stderr"
            exit 1
          }

          # Sort descending
          for (i = 1; i <= num_files; i++) {
            max_idx = i
            for (j = i + 1; j <= num_files; j++) {
              if (sizes[j] > sizes[max_idx]) max_idx = j
            }
            if (max_idx != i) {
              temp = sizes[i]; sizes[i] = sizes[max_idx]; sizes[max_idx] = temp
              temp = paths[i]; paths[i] = paths[max_idx]; paths[max_idx] = temp
            }
          }

          # Output results with colors
          for (i = 1; i <= num_files; i++) {
            if (human) {
              printf "\033[32m%10s\033[0m  %s\n", humanize(sizes[i]), paths[i]
            } else {
              printf "\033[32m%12d\033[0m  %s\n", sizes[i], paths[i]
            }
          }
        }
      '
  fi

  local exit_code=$?

  # Show errors if debug mode or if command failed
  if [[ -s "$error_output" ]] && { (( debug )) || (( exit_code != 0 )); }; then
    print -P "${RED}Errors encountered:${RST}" >&2
    cat "$error_output" >&2
  fi

  rm -f "$error_output"
  return $exit_code
}

# Convert input to all lowercase; accepts args or stdin.
lowercase() {
  emulate -L zsh
  if (( $# )); then
    local s="$*"
    print -r -- "${(L)s}"
  else
    LC_ALL=C tr '[:upper:]' '[:lower:]'
  fi
}

# Convert input to all uppercase; accepts args or stdin.
uppercase() {
  emulate -L zsh
  if (( $# )); then
    local s="$*"
    print -r -- "${(U)s}"
  else
    LC_ALL=C tr '[:lower:]' '[:upper:]'
  fi
}

# Fetch a weather report from wttr.in.
#   weather [-u metric|us] [-1] [location]
weather() {
  emulate -L zsh
  __have curl || { print -u2 "Error: 'curl' is required for the weather function."; return 1; }

  local usage="Usage: weather [-u metric|us] [-1] [location]
  Options:
    -u metric|us  Units: metric (default) or us (imperial)
    -1            Single-line summary
    -h            Help"

  local units="metric" oneline=0 opt
  OPTIND=1
  while getopts ":u:1h" opt; do
    case "$opt" in
      u) units="${OPTARG:l}" ;;
      1) oneline=1 ;;
      h) print -r -- "$usage"; return 0 ;;
      \?) print -u2 "Invalid option: -$OPTARG"; print -r -u2 -- "$usage"; return 1 ;;
    esac
  done
  shift $((OPTIND - 1))

  local location="${1:-}"
  # Determine language from locale settings.
  local lang="${LC_ALL:-$LANG}"
  lang="${lang%%.*}"
  [[ -z "$lang" ]] && lang="en"

  local unit_flag="m"
  [[ "$units" == "us" ]] && unit_flag="u"

  local url
  if ((oneline)); then
    url="https://wttr.in/${location}?${unit_flag}&Q&format=3&lang=${lang}"
  else
    url="https://wttr.in/${location}?${unit_flag}&Q&lang=${lang}"
  fi

  curl -fsS --connect-timeout 3 --max-time 7 "$url" ||
    print -u2 "Weather service wttr.in unavailable or query failed for '${location:-your location}'."
}
