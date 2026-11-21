# bash completion for decaf

_decaf() {
    local -r cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=()

    if ((COMP_CWORD == 1)); then
        mapfile -t COMPREPLY < <(compgen -W "on off status --help --version" -- "$cur")
        return 0
    fi

    # `on`, `off` and `status` take --notify, offered until it has been used.
    # DURATION is free-form seconds, so there is nothing to offer for it.
    case "${COMP_WORDS[1]}" in
    on | off | status) ;;
    *) return 0 ;;
    esac
    local -r used=" ${COMP_WORDS[*]:2:COMP_CWORD-2} "
    [[ "$used" == *" --notify "* ]] ||
        mapfile -t COMPREPLY < <(compgen -W "--notify" -- "$cur")
}

complete -F _decaf decaf
