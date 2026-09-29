#!/usr/bin/env bats
#
# Pure functions, tested by sourcing the script (main does not run).

setup() {
    load helpers
    common_setup
    # shellcheck source=src/decaf
    source "$DECAF"
}

# --- is_duration -------------------------------------------------------------

@test "is_duration accepts whole seconds from 1 to the maximum" {
    local value
    for value in 1 9 10 60 1800 86400 999999999 2147483647; do
        is_duration "$value" || fail "rejected '$value'"
    done
}

@test "is_duration rejects 0 and anything else" {
    local value
    for value in 0 00 "" " " "-1" "+1" "01" "007" "1.5" "1,5" "10m" "1h" \
        " 10" "10 " $'10\n' "1e3" "0x10" "inf" "2147483648" \
        "9999999999" "99999999999999999999999"; do
        if is_duration "$value"; then
            fail "accepted '$value'"
        fi
    done
}

@test "is_duration never evaluates its input as arithmetic" {
    # Bash arithmetic on an unvalidated string can run commands.
    local -r marker="$BATS_TEST_TMPDIR/pwned"
    run is_duration "a[\$(touch $marker)]"
    assert_status 1
    [[ ! -e "$marker" ]] || fail "input was evaluated"
}

# --- format_status -----------------------------------------------------------

@test "format_status: a running timer" {
    run format_status 1800 1759158600 1759158660
    assert_status 0
    assert_output "$(printf '%s\n' state=on duration=1800 started=1759158600 \
        until=1759160400 remaining=1740)"
}

@test "format_status: remaining is 0, never negative, once the deadline passed" {
    run format_status 60 1000 5000
    assert_equal "$(grep '^remaining=' <<<"$output")" "remaining=0"
    assert_equal "$(grep '^until=' <<<"$output")" "until=1060"
}

# --- cli_parse_on ------------------------------------------------------------

usage_hint="Try 'decaf --help' for more information."

@test "cli_parse_on: a duration" {
    run cli_parse_on 1800
    assert_status 0
    assert_output "1800"
}

@test "cli_parse_on: missing duration" {
    run --separate-stderr cli_parse_on
    assert_status 2
    assert_output ""
    assert_stderr "decaf: missing DURATION"$'\n'"$usage_hint"
}

@test "cli_parse_on: invalid duration" {
    local value
    for value in 0 10m -5 01 2147483648; do
        run --separate-stderr cli_parse_on "$value"
        assert_status 2
        assert_stderr "decaf: invalid DURATION '$value': expected whole seconds from 1 to 2147483647"$'\n'"$usage_hint"
    done
}

@test "cli_parse_on: extra argument" {
    run --separate-stderr cli_parse_on 60 120
    assert_status 2
    assert_stderr "decaf: unexpected argument '120'"$'\n'"$usage_hint"
}

@test "cli_parse_on: options are unknown" {
    local value
    for value in --lid --idle -h --now -; do
        run --separate-stderr cli_parse_on 60 "$value"
        assert_status 2
        assert_stderr "decaf: unknown option '$value'"$'\n'"$usage_hint"
    done
}
