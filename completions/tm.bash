# bash completion for tm. "tm link" installs it; bash-completion loads it on the first "tm <Tab>".
# shellcheck shell=bash

_tm_sessions() { # adds the sessions that start with $1, escaped (names may have spaces)
  local s
  while IFS= read -r s; do
    [[ $s == "$1"* ]] && COMPREPLY+=("$(printf '%q' "$s")")
  done < <(tm _sessions 2>/dev/null)
}

_tm() {
  local cur=${COMP_WORDS[COMP_CWORD]} cmd=${COMP_WORDS[1]:-}
  COMPREPLY=()
  if [ "$COMP_CWORD" = 1 ]; then
    mapfile -t COMPREPLY < <(compgen -W "$(tm _commands 2>/dev/null)" -- "$cur")
    return
  fi
  case $cmd in
    attach | create)
      # NAME, then DIR
      if [ "$COMP_CWORD" = 2 ]; then _tm_sessions "$cur"; else compopt -o dirnames 2>/dev/null; mapfile -t COMPREPLY < <(compgen -d -- "$cur"); fi ;;
    detach | kill)
      [ "$COMP_CWORD" = 2 ] && _tm_sessions "$cur" ;;
    rename)
      [ "$COMP_CWORD" = 2 ] && _tm_sessions "$cur" ;;
    open)
      if [[ $cur == -* ]]; then COMPREPLY=(--all); else _tm_sessions "$cur"; fi ;;
    completion)
      [ "$COMP_CWORD" = 2 ] && mapfile -t COMPREPLY < <(compgen -W "bash zsh fish" -- "$cur") ;;
  esac
  return 0
}

complete -F _tm tm
