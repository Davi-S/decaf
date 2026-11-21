# bash completion for decaf

_decaf() {
    local -r cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=()

    if ((COMP_CWORD == 1)); then
        mapfile -t COMPREPLY < <(compgen -W "on off status --help --version" -- "$cur")
        return 0
    fi

    # Only `status` has an option to offer, once: `on` takes free-form
    # seconds, and the other commands take no arguments.
    if [[ "${COMP_WORDS[1]}" == status ]] && ((COMP_CWORD == 2)); then
        mapfile -t COMPREPLY < <(compgen -W "--notify" -- "$cur")
    fi
}

complete -F _decaf decaf
