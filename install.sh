#!/usr/bin/env bash
set -euo pipefail

# ─── Constants ────────────────────────────────────────────────────────────────
readonly ZCORE_REPO_URL="https://github.com/Khodaparastan/zcore"
readonly ZCORE_BRANCH="int"
readonly ZCORE_DEST="${XDG_CONFIG_HOME:-${HOME}/.config}/zsh"
readonly BACKUP_SUFFIX="backup.$(date +%Y%m%d_%H%M%S)"

# ─── Logging ──────────────────────────────────────────────────────────────────
log() { printf '\e[34m[INFO]\e[0m  %s\n' "$*"; }
warn() { printf '\e[33m[WARN]\e[0m  %s\n' "$*" >&2; }
die() {
  printf '\e[31m[ERROR]\e[0m %s\n' "$*" >&2
  exit 1
}

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Backs up a path by renaming it; handles broken symlinks via -L
backup() {
  local src="$1"
  [[ -e "$src" || -L "$src" ]] || return 0
  local dst="${src}.${BACKUP_SUFFIX}"
  mv -- "$src" "$dst"
  warn "Backed up: $src → $dst"
}

# Cross-filesystem safe move: prefer mv, fall back to cp -a + rm
safe_move() {
  local src="$1"
  local dst="$2"

  if mv -- "$src" "$dst" 2>/dev/null; then
    return 0
  fi

  warn "mv failed (cross-device?), falling back to cp+rm"

  # Copy first; only remove source on confirmed success
  cp -a -- "$src" "$dst" || {
    rm -rf -- "$dst"
    die "cp failed: $src → $dst"
  }

  rm -rf -- "$src"
}

# Validates the cloned directory looks like a real populated repo
validate_clone() {
  local dir="$1"
  [[ -d "$dir/.git" ]] || die "Missing .git directory in clone: $dir"
  [[ -f "$dir/.zshrc" ]] || die "Missing .zshrc in cloned repo: $dir"
  [[ -f "$dir/.zshenv" ]] || die "Missing .zshenv in cloned repo: $dir"
}

# ─── Preflight ────────────────────────────────────────────────────────────────
preflight() {
  command -v git &>/dev/null || die "git is not installed or not in PATH"

  local parent_dir="${ZCORE_DEST%/*}"
  # Ensure parent is creatable/writable — mkdir -p will catch real failures later,
  # but an explicit test gives a cleaner error message
  if [[ -e "$parent_dir" && ! -w "$parent_dir" ]]; then
    die "Parent directory is not writable: $parent_dir"
  fi
}

# ─── Backup existing files ────────────────────────────────────────────────────
run_backups() {
  backup "$ZCORE_DEST"
  backup "${HOME}/.zshrc"
  backup "${HOME}/.zshenv"
}

# ─── Clone repo into a temp directory ────────────────────────────────────────
clone_repo() {
  # Restrict temp dir permissions from the start
  local old_umask
  old_umask="$(umask)"
  umask 077
  TEMPDIR="$(mktemp -d)"
  umask "$old_umask"

  # Always clean up TEMPDIR on exit; trap - EXIT clears this after safe_move
  trap 'rm -rf -- "${TEMPDIR:-}"' EXIT

  log "Cloning ${ZCORE_REPO_URL} (branch: ${ZCORE_BRANCH})…"
  git clone \
    --branch "$ZCORE_BRANCH" \
    --depth 1 \
    --quiet \
    -- \
    "$ZCORE_REPO_URL" \
    "$TEMPDIR"

  validate_clone "$TEMPDIR"
}

# ─── Install cloned repo to final destination ─────────────────────────────────
install_repo() {
  local parent_dir="${ZCORE_DEST%/*}"
  mkdir -p -- "$parent_dir"
  safe_move "$TEMPDIR" "$ZCORE_DEST"

  # TEMPDIR has been moved — cancel the EXIT cleanup
  trap - EXIT
  log "Installed to ${ZCORE_DEST}"
}

# ─── Create symlinks in HOME ──────────────────────────────────────────────────
create_symlinks() {
  local file src_file link

  for file in .zshrc .zshenv; do
    src_file="${ZCORE_DEST}/${file}"
    link="${HOME}/${file}"

    [[ -e "$src_file" || -L "$src_file" ]] ||
      die "Expected file missing in installed repo: $src_file"

    ln -sf -- "$src_file" "$link"
    log "Linked: $link → $src_file"
  done
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  preflight
  run_backups
  clone_repo
  install_repo
  create_symlinks
  log "Done. Restart your shell or run: exec zsh"
}

main "$@"
