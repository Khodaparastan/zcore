#!/usr/bin/env zsh
export ZDOTDIR="$HOME/.config/zsh"
init() {
  [[ -r "$ZDOTDIR/init.zsh" ]] && source "$ZDOTDIR/init.zsh"
}
init
