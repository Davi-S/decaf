#!/usr/bin/env bats
#
# Tests for the test infrastructure itself: the fakes and the helpers.

setup() {
    load helpers
    common_setup
}

@test "every faked command resolves to the fake" {
    local cmd
    for cmd in "${FAKED_COMMANDS[@]}"; do
        assert_equal "$(command -v "$cmd")" "$FAKE_DIR/bin/$cmd"
    done
}

@test "a call without rules prints nothing and succeeds" {
    run --separate-stderr systemctl --user stop app-decaf.service
    assert_status 0
    assert_output ""
    assert_stderr ""
}

@test "calls are logged with their arguments" {
    systemctl --user show app-decaf.service
    date +%s
    assert_called systemctl --user show app-decaf.service
    assert_called date +%s
    assert_equal "$(calls | wc -l)" 2
}

@test "arguments with spaces are logged exactly" {
    systemd-run -p "ExecStopPost=decaf _stopped" --unit=app-decaf
    assert_called systemd-run -p "ExecStopPost=decaf _stopped" --unit=app-decaf
    run assert_called systemd-run -p ExecStopPost=decaf _stopped --unit=app-decaf
    assert_status 1
}

@test "a rule sets stdout and exit code" {
    fake systemctl --stdout "inactive" --exit 3
    run systemctl --user is-active app-decaf.service
    assert_status 3
    assert_output "inactive"
}

@test "multi-line stdout is printed as given" {
    fake systemctl --stdout $'line one\nline two'
    run systemctl anything
    assert_output $'line one\nline two'
}

@test "rules only apply to calls matching their pattern" {
    fake systemctl --args "*is-active*" --stdout "active"
    run systemctl --user is-active app-decaf.service
    assert_output "active"
    run systemctl --user show app-decaf.service
    assert_output ""
}

@test "the last registered matching rule wins" {
    fake date --stdout "1000"
    fake date --args "+%s" --stdout "2000"
    run date +%s
    assert_output "2000"
    run date -d @0
    assert_output "1000"
}

@test "calls CMD filters the log by command" {
    systemctl a
    systemd-run b
    systemctl c
    assert_equal "$(calls systemctl)" $'systemctl a\nsystemctl c'
}

@test "refute_called passes and fails correctly" {
    refute_called notify-send
    notify-send hello
    run refute_called notify-send
    assert_status 1
}

@test "assertions fail with a message" {
    run --separate-stderr assert_equal "a" "b"
    assert_status 1
    assert_stderr $'expected:\nb\nactual:\na'
}

@test "a --once rule answers one call, then the next rule applies" {
    fake date --stdout "2000"
    fake date --stdout "1000" --once
    assert_equal "$(date +%s)" "1000"
    assert_equal "$(date +%s)" "2000"
    assert_equal "$(date +%s)" "2000"
}

@test "a --hang rule prints, then runs until killed" {
    fake gdbus --stdout "signal" --hang
    local line fd
    exec {fd}< <(gdbus monitor)
    local -r pid=$!
    read -r -t 5 -u "$fd" line || fail "no line printed"
    assert_equal "$line" "signal"
    kill -0 "$pid" || fail "exited instead of hanging"
    run refute_hanging gdbus
    assert_status 1
    refute_hanging gdbus # the failed check above killed it
    exec {fd}<&-
}

@test "concurrent calls are logged as whole lines" {
    # The waiter runs gdbus in the background while other commands run; the
    # fakes must not interleave their log lines.
    local i
    for ((i = 0; i < 40; i++)); do
        systemctl --user show app-decaf.service &
        gdbus monitor --system --dest org.freedesktop.login1 &
    done
    wait
    assert_equal "$(calls | wc -l)" 80
    assert_equal "$(grep -cvxE '(systemctl --user show app-decaf\.service|gdbus monitor --system --dest org\.freedesktop\.login1)' "$FAKE_DIR/calls.log")" 0
}
