#!/usr/bin/env zsh
export ZDOTDIR="$HOME/.config/zsh"
init() {
  [[ -r "$ZDOTDIR/init" ]] && source "$ZDOTDIR/init"
}
init
