#!/usr/bin/env bats
#
# Bash completion, tested by calling the completion function the way bash does.

setup() {
    load helpers
    # shellcheck source=completions/decaf.bash
    source "$PROJECT_ROOT/completions/decaf.bash"
}

# complete_words WORD...: complete the last WORD of "decaf WORD...", then print
# the candidates on one line.
complete_words() {
    COMP_WORDS=(decaf "$@")
    COMP_CWORD=$#
    COMPREPLY=()
    _decaf
    printf '%s\n' "${COMPREPLY[*]}"
}

@test "the first word completes to the public commands" {
    assert_equal "$(complete_words "")" "on off status --help --version"
}

@test "internal commands are never offered" {
    assert_equal "$(complete_words "_")" ""
}

@test "a partial command completes" {
    assert_equal "$(complete_words "o")" "on off"
    assert_equal "$(complete_words "st")" "status"
    assert_equal "$(complete_words "--h")" "--help"
}

@test "nothing to suggest after a command" {
    local cmd
    for cmd in on off status --help --version; do
        assert_equal "$(complete_words "$cmd" "")" ""
    done
    assert_equal "$(complete_words on "18")" ""
}
