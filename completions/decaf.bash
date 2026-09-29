# bash completion for decaf

_decaf() {
    local -r cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=()

    # Only the command is completed: `on` takes free-form seconds, and the
    # other commands take no arguments.
    if ((COMP_CWORD == 1)); then
        mapfile -t COMPREPLY < <(compgen -W "on off status --help --version" -- "$cur")
    fi
}

complete -F _decaf decaf
