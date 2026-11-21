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

@test "after on, off and status: --notify, once" {
    local cmd
    for cmd in on off status; do
        assert_equal "$(complete_words "$cmd" "")" "--notify"
        assert_equal "$(complete_words "$cmd" "--n")" "--notify"
        assert_equal "$(complete_words "$cmd" --notify "")" ""
    done
    assert_equal "$(complete_words on 1800 "")" "--notify"
    assert_equal "$(complete_words on --notify 1800 "")" ""
}

@test "nothing to suggest after the other commands, or for a duration" {
    local cmd
    for cmd in --help --version; do
        assert_equal "$(complete_words "$cmd" "")" ""
    done
    assert_equal "$(complete_words on "18")" ""
}
