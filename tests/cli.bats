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
    for cmd in off status --help --version _wait _stopped; do
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

# --- _wait (the timer unit's main process) -----------------------------------
# 1759158600 (S) is Mon 2025-09-29 15:10 UTC; tests run with TZ=UTC.
# With DURATION 1800 the deadline (D) is 15:40 and the warning is due at D-60.

readonly S=1759158600 D=1759160400
readonly MONITOR_ARGS=(monitor --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1)
readonly RESUME_SIGNAL="/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (false,)"

# timer_env DURATION STARTED: the environment the unit gives _wait and _stopped.
timer_env() {
    export DECAF_DURATION="$1" DECAF_STARTED="$2"
}

# clock T1 T2 ... TN: successive `date +%s` answers; the last one repeats.
clock() {
    local -r times=("$@")
    fake_now "${times[-1]}"
    local i
    for ((i = ${#times[@]} - 2; i >= 0; i--)); do
        fake date --args "+%s" --stdout "${times[i]}" --once
    done
}

assert_notified() { # EXPIRE_MS URGENCY TITLE BODY
    assert_called notify-send --app-name=decaf "--expire-time=$1" "--urgency=$2" "$3" "$4"
}

assert_notifications() { # COUNT
    assert_equal "$(calls notify-send | wc -l)" "$1"
}

@test "_wait: announces, warns 60 s before, then suspends at the deadline" {
    timer_env 1800 "$S"
    fake gdbus --hang # a quiet monitor: only the timeouts end each wait
    # Clock reads: announce; 1 s before the warning, then at it; 1 s before
    # the deadline, then at it. So the test waits 2 seconds in total.
    clock "$S" $((D - 61)) $((D - 60)) $((D - 1)) "$D"
    SECONDS=0
    run --separate-stderr "$DECAF" _wait
    assert_status 0
    assert_stderr ""
    ((SECONDS <= 4)) || fail "took $SECONDS s"
    assert_notified 2000 normal "Decaf on" "Suspending at 15:40"
    assert_notified 6000 normal "Suspending soon" "At 15:40 · run 'decaf off' to cancel"
    assert_notifications 2
    assert_called systemctl suspend -i
    assert_called gdbus "${MONITOR_ARGS[@]}"
    refute_called sleep
    refute_hanging gdbus
}

@test "_wait: resuming inside the last minute warns at once, then suspends" {
    timer_env 1800 "$S"
    fake gdbus --stdout "$RESUME_SIGNAL" --hang
    # Asleep through the warning time; resumed 20 s before the deadline.
    clock "$S" "$S" $((D - 20)) $((D - 20)) "$D"
    SECONDS=0
    run --separate-stderr "$DECAF" _wait
    assert_status 0
    ((SECONDS <= 2)) || fail "took $SECONDS s: it waited instead of rechecking"
    assert_notified 6000 normal "Suspending soon" "At 15:40 · run 'decaf off' to cancel"
    assert_called systemctl suspend -i
    refute_hanging gdbus
}

@test "_wait: asleep at the deadline: skips, without warning or suspending" {
    timer_env 1800 "$S"
    fake gdbus --stdout "$RESUME_SIGNAL" --hang
    # Asleep through the warning time and the deadline; resumed 10 min later.
    clock "$S" "$S" $((D + 600))
    run --separate-stderr "$DECAF" _wait
    assert_status 10
    assert_stderr ""
    assert_notifications 1 # only "Decaf on"
    refute_called systemctl
    refute_hanging gdbus
}

@test "_wait: noticing the deadline up to 5 s late still suspends; later skips" {
    timer_env 30 "$S" # 30 s: no warning
    clock "$S" $((S + 35))
    run "$DECAF" _wait
    assert_status 0
    assert_called systemctl suspend -i

    : >"$FAKE_DIR/calls.log"
    clock "$S" $((S + 36))
    run "$DECAF" _wait
    assert_status 10
    refute_called systemctl
}

@test "_wait: no warning for a timer of 60 s or less" {
    timer_env 60 "$S"
    fake gdbus --stdout "$RESUME_SIGNAL" --hang
    # Awake at the start, which is already "60 s before the deadline".
    clock "$S" "$S" $((S + 60))
    run "$DECAF" _wait
    assert_status 0
    assert_notifications 1
    assert_notified 2000 normal "Decaf on" "Suspending at 15:11"
}

@test "_wait: without the logind monitor, falls back to sleep and warns" {
    timer_env 30 "$S"
    # gdbus exits at once (no rule). Clock reads: announce, first check,
    # recheck after the monitor died, after the sleep.
    clock "$S" "$S" "$S" $((S + 30))
    run --separate-stderr "$DECAF" _wait
    assert_status 0
    assert_stderr "decaf: cannot watch logind for resume; after a suspend, the timer may end late"
    assert_called sleep 30
    assert_called systemctl suspend -i
}

@test "_wait: a failed notification does not cancel the timer" {
    timer_env 30 "$S"
    fake notify-send --exit 1
    clock "$S" $((S + 30))
    run --separate-stderr "$DECAF" _wait
    assert_status 0
    assert_stderr "decaf: could not send a notification"
    assert_called systemctl suspend -i
}

@test "_wait: an unreadable clock while waiting never suspends" {
    timer_env 30 "$S"
    fake gdbus --stdout "$RESUME_SIGNAL" --hang
    clock "$S" "$S" "not a number"
    run --separate-stderr "$DECAF" _wait
    assert_status 4
    assert_stderr "decaf: could not read the current time"
    refute_called systemctl
    refute_hanging gdbus
}

@test "_wait: a refused suspend is a system error" {
    timer_env 30 "$S"
    fake systemctl --args "suspend -i" --exit 1
    clock "$S" $((S + 30))
    run --separate-stderr "$DECAF" _wait
    assert_status 4
    assert_stderr "decaf: could not suspend"
}

@test "_wait: missing or invalid timer values are a system error" {
    run --separate-stderr "$DECAF" _wait
    assert_status 4
    assert_stderr "decaf: missing or invalid DECAF_* variables; '_wait' and '_stopped' are run by the timer unit"
    refute_called notify-send
    refute_called systemctl

    timer_env 0 "$S"
    run "$DECAF" _wait
    assert_status 4
}

# --- _stopped (the unit's ExecStopPost) --------------------------------------

@test "_stopped: suspended: no notification" {
    timer_env 1800 "$S"
    EXIT_CODE=exited EXIT_STATUS=0 run "$DECAF" _stopped
    assert_status 0
    refute_called notify-send
}

@test "_stopped: skipped" {
    timer_env 1800 "$S"
    fake_now $((D + 600))
    EXIT_CODE=exited EXIT_STATUS=10 run "$DECAF" _stopped
    assert_status 0
    assert_notified 2000 normal "Decaf off" "Skipped: the system was asleep at 15:40"
}

@test "_stopped: skipped, with invalid timer values, is a system error" {
    EXIT_CODE=exited EXIT_STATUS=10 run --separate-stderr "$DECAF" _stopped
    assert_status 4
    refute_called notify-send
}

@test "_stopped: turned off" {
    EXIT_CODE=killed EXIT_STATUS=TERM run "$DECAF" _stopped
    assert_status 0
    assert_notified 2000 normal "Decaf off" "Turned off"
}

@test "_stopped: failed" {
    EXIT_CODE=exited EXIT_STATUS=4 run "$DECAF" _stopped
    assert_status 0
    assert_notified 2000 critical "Decaf failed" "Could not suspend. See: journalctl --user -u app-decaf"
}

@test "_stopped: no exit information counts as failed" {
    run "$DECAF" _stopped
    assert_notified 2000 critical "Decaf failed" "Could not suspend. See: journalctl --user -u app-decaf"
}

@test "_stopped: a failed notification is a system error" {
    fake notify-send --exit 1
    EXIT_CODE=killed EXIT_STATUS=TERM run --separate-stderr "$DECAF" _stopped
    assert_status 4
    assert_stderr "decaf: could not send a notification"
}
