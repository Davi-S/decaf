# bash completion for decaf

_decaf() {
    local -r cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=()

    if ((COMP_CWORD == 1)); then
        mapfile -t COMPREPLY < <(compgen -W "start stop status menu help version" -- "$cur")
    elif ((COMP_CWORD == 2)) && [[ "${COMP_WORDS[1]}" == start ]]; then
        mapfile -t COMPREPLY < <(compgen -W "15m 30m 1h 2h" -- "$cur")
    fi
}

complete -F _decaf decaf
