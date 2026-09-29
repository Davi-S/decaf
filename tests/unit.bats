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

# --- is_timestamp, is_safe_path ----------------------------------------------

@test "is_timestamp accepts up to 12 digits without leading zeros" {
    local value
    for value in 0 1 1759158600 999999999999; do
        is_timestamp "$value" || fail "rejected '$value'"
    done
    for value in "" -1 01 1.5 1759158600x 1000000000000; do
        if is_timestamp "$value"; then
            fail "accepted '$value'"
        fi
    done
}

@test "is_safe_path accepts absolute paths of plain characters only" {
    local value
    for value in /usr/bin/decaf /home/me/src/decaf-2.0/src/decaf /opt/a_b+c/decaf; do
        is_safe_path "$value" || fail "rejected '$value'"
    done
    # shellcheck disable=SC2016 # a literal $ is the point
    for value in "" decaf ./decaf "/my tools/decaf" '/a$b/decaf' /a%b/decaf '/a"b' "/a;b"; do
        if is_safe_path "$value"; then
            fail "accepted '$value'"
        fi
    done
}

# --- parse_timer_values, parse_unit_properties -------------------------------

@test "parse_timer_values accepts valid values and prints them" {
    run parse_timer_values 1800 1759158600
    assert_status 0
    assert_output "1800 1759158600"
}

@test "parse_timer_values rejects any invalid value" {
    local values
    for values in "0 1" "60m 1" "60 x" "60 01"; do
        # shellcheck disable=SC2086 # split into two arguments on purpose
        run parse_timer_values $values
        assert_status 1
    done
    run parse_timer_values "" ""
    assert_status 1
}

@test "parse_unit_properties: an inactive or unknown unit" {
    run parse_unit_properties $'ActiveState=inactive\nEnvironment='
    assert_status 0
    assert_output "inactive"
}

@test "parse_unit_properties: every state other than active is inactive" {
    local state
    for state in failed activating deactivating reloading; do
        run parse_unit_properties "ActiveState=$state"$'\nEnvironment='
        assert_output "inactive"
    done
}

@test "parse_unit_properties: an active unit" {
    run parse_unit_properties $'ActiveState=active\nEnvironment=DECAF_STARTED=1759158600 DECAF_DURATION=1800'
    assert_status 0
    assert_output "active 1800 1759158600"
}

@test "parse_unit_properties: property and variable order do not matter" {
    run parse_unit_properties $'Environment=DECAF_DURATION=60 DECAF_STARTED=5\nActiveState=active'
    assert_output "active 60 5"
}

@test "parse_unit_properties: an active unit with missing or invalid values fails" {
    local environment
    for environment in \
        "" \
        "DECAF_STARTED=1" \
        "DECAF_STARTED=1 DECAF_DURATION=0" \
        "DECAF_STARTED=1 DECAF_DURATION=60m" \
        "DECAF_STARTED=x DECAF_DURATION=60" \
        "OTHER=* DECAF_DURATION=60"; do
        run parse_unit_properties "ActiveState=active"$'\n'"Environment=$environment"
        assert_status 1
        assert_output ""
    done
}

# --- format_at, stop_reason --------------------------------------------------
# 1759158600 is Mon 2025-09-29 15:10 UTC; tests run with TZ=UTC.

@test "format_at: time only when the moment is today" {
    assert_equal "$(format_at 1759160400 1759158600)" "15:40"
}

@test "format_at: weekday when within 6 days" {
    assert_equal "$(format_at 1759421400 1759158600)" "Thu 16:10"
}

@test "format_at: full date when further away" {
    assert_equal "$(format_at 1761750600 1759158600)" "2025-10-29 15:10"
}

@test "format_at: a moment in the past today is still a time" {
    assert_equal "$(format_at 1759158000 1759158600)" "15:00"
}

@test "format_at: English weekdays whatever the locale" {
    local -r locale="$(locale -a 2>/dev/null | grep -iE '^(pt_BR|de_DE|fr_FR)\.utf-?8$' | head -1)"
    [[ -n "$locale" ]] || skip "no non-English locale installed"
    LC_ALL="$locale"
    assert_equal "$(format_at 1759421400 1759158600)" "Thu 16:10"
}

@test "stop_reason maps the waiter's exit information to how the timer ended" {
    assert_equal "$(stop_reason exited 0)" "suspended"
    assert_equal "$(stop_reason exited 10)" "skipped"
    assert_equal "$(stop_reason killed TERM)" "stopped"
    assert_equal "$(stop_reason killed KILL)" "stopped"
    assert_equal "$(stop_reason exited 1)" "failed"
    assert_equal "$(stop_reason exited 4)" "failed"
    assert_equal "$(stop_reason dumped SEGV)" "failed"
    assert_equal "$(stop_reason "" "")" "failed"
}
