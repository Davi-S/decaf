#!/usr/bin/env bats
#
# The command line, run as a real process with every external command faked.

setup() {
    load helpers
    common_setup
}

usage_hint="Try 'decaf --help' for more information."

@test "--help prints usage to stdout and succeeds" {
    run --separate-stderr "$DECAF" --help
    assert_status 0
    assert_stderr ""
    [[ "${lines[0]}" == "Usage: decaf on DURATION" ]] ||
        fail "unexpected first line: ${lines[0]}"
}

@test "--version prints the version" {
    run --separate-stderr "$DECAF" --version
    assert_status 0
    [[ "$output" =~ ^decaf\ [0-9]+\.[0-9]+\.[0-9]+$ ]] ||
        fail "unexpected output: $output"
}

@test "no command is a usage error" {
    run --separate-stderr "$DECAF"
    assert_status 2
    assert_output ""
    assert_stderr "decaf: missing command"$'\n'"$usage_hint"
}

@test "an unknown command is a usage error" {
    local cmd
    for cmd in start stop menu trigger help version; do
        run --separate-stderr "$DECAF" "$cmd"
        assert_status 2
        assert_stderr "decaf: unknown command '$cmd'"$'\n'"$usage_hint"
    done
}

@test "commands without arguments reject arguments" {
    local cmd
    for cmd in off status --help --version; do
        run --separate-stderr "$DECAF" "$cmd" extra
        assert_status 2
        assert_stderr "decaf: '$cmd' takes no arguments"$'\n'"$usage_hint"
    done
}

@test "usage errors never touch the system" {
    run "$DECAF" on 10m
    assert_status 2
    assert_equal "$(calls)" ""
}
