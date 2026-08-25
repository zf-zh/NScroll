# nscroll(1) completion                                    -*- shell-script -*-

_nscroll() {
  # Every invocation is exactly one word; a second argument is a usage error.
  [[ $COMP_CWORD -eq 1 ]] || return 0

  local cur=${COMP_WORDS[1]}
  if [[ $cur == -* ]]; then
    COMPREPLY=($(compgen -W '-h --help -V --version' -- "$cur"))
  else
    COMPREPLY=($(compgen -W 'run enable disable restart status help version' -- "$cur"))
  fi
}

complete -F _nscroll nscroll
