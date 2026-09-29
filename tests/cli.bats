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

# --- helpers for the timer's state -------------------------------------------

readonly SHOW_ARGS="--user show --property=ActiveState --property=Environment app-decaf.service"

# fake_timer_off: systemd reports no timer unit.
fake_timer_off() {
    fake systemctl --args "$SHOW_ARGS" --stdout $'ActiveState=inactive\nEnvironment='
}

# fake_timer_on DURATION STARTED: systemd reports a running timer unit.
fake_timer_on() {
    fake systemctl --args "$SHOW_ARGS" --stdout "ActiveState=active"$'\n'"Environment=DECAF_STARTED=$2 DECAF_DURATION=$1"
}

# fake_now TIMESTAMP: the current time, as `date +%s` prints it.
fake_now() {
    fake date --args "+%s" --stdout "$1"
}

# assert_timer_started DURATION STARTED: systemd-run was called exactly as the
# design specifies.
assert_timer_started() {
    assert_called systemd-run --user --quiet --collect \
        --unit=app-decaf.service --slice=app.slice \
        "--description=decaf: suspend the system after a while" \
        "--setenv=DECAF_STARTED=$2" \
        "--setenv=DECAF_DURATION=$1" \
        "--property=ExecStopPost=$DECAF _stopped" \
        --property=SuccessExitStatus=10 \
        -- "$DECAF" _wait
}

# --- status ------------------------------------------------------------------

@test "status: no timer" {
    fake_timer_off
    run --separate-stderr "$DECAF" status
    assert_status 1
    assert_output "state=off"
    assert_stderr ""
}

@test "status: a running timer" {
    fake_timer_on 1800 1759158600
    fake_now 1759158660
    run --separate-stderr "$DECAF" status
    assert_status 0
    assert_output "$(printf '%s\n' state=on duration=1800 started=1759158600 \
        until=1759160400 remaining=1740)"
    assert_stderr ""
}

@test "status: systemd unreachable is a system error" {
    fake systemctl --args "$SHOW_ARGS" --exit 1
    run --separate-stderr "$DECAF" status
    assert_status 4
    assert_output ""
    assert_stderr "decaf: could not read the timer state from systemd"
}

@test "status: a unit decaf did not create is a system error" {
    fake systemctl --args "$SHOW_ARGS" --stdout $'ActiveState=active\nEnvironment=FOO=bar'
    run --separate-stderr "$DECAF" status
    assert_status 4
    assert_stderr "decaf: app-decaf.service is running but was not started by this version of decaf"
}

@test "status: an unreadable clock is a system error" {
    fake_timer_on 60 1759158600
    fake date --args "+%s" --stdout "not a number"
    run --separate-stderr "$DECAF" status
    assert_status 4
    assert_stderr "decaf: could not read the current time"
}

# --- on ----------------------------------------------------------------------

@test "on: starts the timer unit" {
    fake_timer_off
    fake_now 1759158600
    run --separate-stderr "$DECAF" on 1800
    assert_status 0
    assert_output ""
    assert_stderr ""
    assert_timer_started 1800 1759158600
}

@test "on: a running timer is not replaced" {
    fake_timer_on 60 1759158600
    run --separate-stderr "$DECAF" on 1800
    assert_status 3
    assert_output ""
    assert_stderr "decaf: a timer is already on; run 'decaf off' first"
    refute_called systemd-run
}

@test "on: systemd-run failing is a system error" {
    fake_timer_off
    fake_now 1759158600
    fake systemd-run --exit 1
    run --separate-stderr "$DECAF" on 60
    assert_status 4
    assert_stderr "decaf: could not start the timer"
}

@test "on: refuses to run from a path systemd would misread" {
    local -r dir="$BATS_TEST_TMPDIR/my tools"
    mkdir -p "$dir"
    cp "$DECAF" "$dir/decaf"
    fake_timer_off
    fake_now 1759158600
    run --separate-stderr "$dir/decaf" on 60
    assert_status 4
    assert_stderr "decaf: cannot run from '$dir/decaf': the path may only contain letters, digits and / . _ + -"
    refute_called systemd-run
}

# --- off ---------------------------------------------------------------------

@test "off: stops the timer unit" {
    fake_timer_on 60 1759158600
    run --separate-stderr "$DECAF" off
    assert_status 0
    assert_output ""
    assert_stderr ""
    assert_called systemctl --user stop app-decaf.service
}

@test "off: no timer" {
    fake_timer_off
    run --separate-stderr "$DECAF" off
    assert_status 1
    assert_stderr "decaf: no timer is on"
    [[ "$(calls systemctl)" != *" stop "* ]] || fail "stop was called"
}

@test "off: systemctl stop failing is a system error" {
    fake_timer_on 60 1759158600
    fake systemctl --args "--user stop *" --exit 1
    run --separate-stderr "$DECAF" off
    assert_status 4
    assert_stderr "decaf: could not stop the timer"
}
