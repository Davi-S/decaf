#!/usr/bin/env bash
#
# Integration test against the real systemd and logind. Run it on your desktop
# session before each release; CI can't, it has no systemd user session.
#
# Usage: tests/integration.sh [--suspend]
#   (or: make integration, make integration SUSPEND=1)
#
#   Without options: automatic checks, a few seconds. They NEVER suspend: every
#                    timer is turned off long before its deadline.
#   --suspend:       then three checks that suspend the machine, each started
#                    only after you press Enter:
#                      1. decaf suspends at the deadline, overriding a sleep lock
#                      2. asleep at the deadline: the timer is skipped on resume
#                      3. resuming inside the last minute: the warning appears
#
# Tests src/decaf by default. To test an installed copy instead:
#   DECAF=/usr/bin/decaf tests/integration.sh
#
# It refuses to run while a timer is on, so it never touches a timer you started.
# You will see a few notifications while it runs.

set -euo pipefail

DECAF="${DECAF:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/src/decaf}"
readonly DECAF

suspend_checks=false
case "${1-}" in
"") ;;
--suspend) suspend_checks=true ;;
*)
    echo "usage: $0 [--suspend]" >&2
    exit 2
    ;;
esac

failures=0

pass() {
    printf '  ok    %s\n' "$1"
}

fail() {
    printf '  FAIL  %s\n' "$1"
    failures=$((failures + 1))
}

# check DESCRIPTION EXPECTED ACTUAL
check() {
    if [[ "$3" == "$2" ]]; then
        pass "$1"
    else
        fail "$1: expected '$2', got '$3'"
    fi
}

# check_range DESCRIPTION MIN MAX VALUE
check_range() {
    if (($4 >= $2 && $4 <= $3)); then
        pass "$1 ($4)"
    else
        fail "$1: expected $2 to $3, got $4"
    fi
}

# confirm QUESTION: ask the user; passes on "y".
confirm() {
    local answer
    read -rp "  $1 [y/n] " answer
    if [[ "$answer" == y* ]]; then
        pass "$1"
    else
        fail "$1"
    fi
}

section() {
    printf '\n%s\n' "$1"
}

# code ARG...: print decaf's exit code, discarding its output.
code() {
    local -i status=0
    "$DECAF" "$@" >/dev/null 2>&1 || status=$?
    printf '%s\n' "$status"
}

# field KEY: print one value from `decaf status`.
field() {
    "$DECAF" status 2>/dev/null | sed -n "s/^$1=//p" || true
}

# unit_property NAME: one property of the timer unit, as systemd reports it.
unit_property() {
    systemctl --user show --value --property="$1" app-decaf.service
}

# now_ms: the wall clock in milliseconds.
now_ms() {
    local -r us="${EPOCHREALTIME/./}"
    printf '%s\n' "$((us / 1000))"
}

# at SECONDS: a Unix time as HH:MM:SS.
at() {
    printf '%(%H:%M:%S)T\n' "$1"
}

# observe AFTER_OFF MAX
# Poll every 0.1 s until the timer is off, then AFTER_OFF more seconds (at most
# MAX seconds in all). While the machine is suspended this script is frozen
# too, so a jump of more than 5 s between two polls is a suspend. Sets:
#   gap_starts, gap_ends  each suspend's start and end, in ms
#   off_ms                when the timer was first seen off, in ms
observe() {
    gap_starts=()
    gap_ends=()
    off_ms=""
    local -r limit=$(($(now_ms) + $2 * 1000))
    local last now stop_at=""
    last="$(now_ms)"
    while true; do
        now="$(now_ms)"
        if ((now - last > 5000)); then
            gap_starts+=("$last")
            gap_ends+=("$now")
        fi
        last="$now"
        if [[ -z "$off_ms" && "$(code status)" == 1 ]]; then
            off_ms="$(now_ms)"
            stop_at=$((off_ms + $1 * 1000))
        fi
        if [[ -n "$stop_at" ]] && ((now >= stop_at)); then
            break
        fi
        ((now < limit)) || break
        sleep 0.1
    done
}

inhibit_pid=""

# Leave no timer or test lock behind if the script stops halfway.
cleanup() {
    if [[ "$(code status)" == 0 ]]; then
        "$DECAF" off >/dev/null 2>&1 || true
    fi
    if [[ -n "$inhibit_pid" ]]; then
        kill "$inhibit_pid" 2>/dev/null || true
    fi
}

printf 'Testing %s (%s)\n' "$DECAF" "$("$DECAF" --version)"

if [[ "$(code status)" != 1 ]]; then
    echo "A timer is on, or systemd is unreachable. Run 'decaf off' first." >&2
    exit 1
fi
trap cleanup EXIT
test_start="$(date +%s)"
readonly test_start

# -----------------------------------------------------------------------------
section "A 10-minute timer, turned off (never suspends)"

check "on succeeds" 0 "$(code on 600)"
check "status says on" on "$(field state)"
check "duration" 600 "$(field duration)"
started="$(field started)"
check "until = started + duration" "$((started + 600))" "$(field until)"
check_range "remaining" 598 600 "$(field remaining)"
check "the unit is running" active "$(unit_property ActiveState)"
check "the unit is in app.slice" app.slice "$(unit_property Slice)"
check "the unit counts exit 10 (skipped) as success" 10 "$(unit_property SuccessExitStatus)"
check "on again is refused (exit 3)" 3 "$(code on 60)"
check "off succeeds" 0 "$(code off)"
check "off is synchronous: status is off right after" 1 "$(code status)"
check "off again: no timer (exit 1)" 1 "$(code off)"

# -----------------------------------------------------------------------------
section "Usage errors"

check "on 0 is a usage error (exit 2)" 2 "$(code on 0)"
check "on 10m is a usage error (exit 2)" 2 "$(code on 10m)"
check "and start nothing" 1 "$(code status)"

# -----------------------------------------------------------------------------
section "Journal"

if journal="$(journalctl --user -u app-decaf.service --since "@$test_start" -o cat 2>/dev/null)"; then
    check "no errors from decaf in the unit's journal" "" "$(grep '^decaf:' <<<"$journal" || true)"
    check "the unit never failed" "" "$(grep -i 'failed' <<<"$journal" || true)"
else
    fail "could not read the journal (journalctl --user)"
fi

cat <<'EOF'

  You should have seen two notifications, each for about 2 seconds:
    Decaf on   Suspending at HH:MM
    Decaf off  Turned off
EOF

# -----------------------------------------------------------------------------
if [[ "$suspend_checks" == true ]]; then
    section "Suspend check 1: decaf suspends at the deadline, overriding a sleep lock"
    cat <<'EOF'
  A 20-second timer starts while another program holds a lock that blocks
  suspend (like expresso would). Suspending past it needs your password: a
  prompt appears at the deadline; type it within 25 s. decaf must then
  suspend. When the machine is asleep, wake it (open the lid or press a key).
EOF
    read -rp "  Press Enter to start... "
    systemd-inhibit --what=sleep --who=decaf-integration --why="decaf must override this" \
        --mode=block sleep 600 &
    inhibit_pid=$!
    sleep 0.5
    check "on succeeds" 0 "$(code on 20)"
    until="$(field until)"
    printf '  The machine suspends at %s.\n' "$(at "$until")"
    observe 15 600
    kill "$inhibit_pid" 2>/dev/null || true
    inhibit_pid=""
    check "the machine suspended once" 1 "${#gap_starts[@]}"
    if ((${#gap_starts[@]} >= 1)); then
        # Includes typing the password (the prompt allows 25 s).
        check_range "it suspended at the deadline (ms after it, password included)" \
            -1000 30000 $((gap_starts[0] - until * 1000))
    fi
    check "no timer is left" 1 "$(code status)"
    confirm "No 'Suspending soon' warning appeared (the timer was 20 s)?"

    section "Suspend check 2: asleep at the deadline, the timer is skipped"
    cat <<'EOF'
  A 40-second timer starts. Suspend the machine yourself BEFORE its deadline
  (close the lid), and resume AFTER the time shown. decaf must not suspend
  again on resume: it skips, and says so.
EOF
    read -rp "  Press Enter to start... "
    check "on succeeds" 0 "$(code on 40)"
    until="$(field until)"
    printf '  Suspend now, before %s. Resume after %s.\n' "$(at "$until")" "$(at $((until + 20)))"
    observe 15 900
    check "the machine suspended once (yours; no second suspend on resume)" 1 "${#gap_starts[@]}"
    if ((${#gap_starts[@]} >= 1)); then
        if ((gap_starts[0] < until * 1000 - 1000 && gap_ends[0] > until * 1000 + 5000)); then
            pass "you suspended before the deadline and resumed after it"
            if [[ -n "$off_ms" ]]; then
                check_range "the timer ended right after resume (ms)" 0 2000 $((off_ms - gap_ends[0]))
            else
                fail "the timer did not end after resume"
            fi
        else
            fail "the suspend did not span the deadline (suspend before $(at "$until"), resume after $(at $((until + 5))))"
        fi
    fi
    confirm "Did you see 'Decaf off · Skipped: the system was asleep at HH:MM'?"

    section "Suspend check 3: resuming inside the last minute shows the warning"
    cat <<'EOF'
  A 2-minute timer starts. Suspend now, and resume within its LAST MINUTE
  (the window below; aim for the middle). "Suspending soon" must appear right
  away. The machine then suspends at the deadline: wake it again after that.
EOF
    read -rp "  Press Enter to start... "
    check "on succeeds" 0 "$(code on 120)"
    until="$(field until)"
    printf '  Suspend now. Resume between %s and %s.\n' "$(at $((until - 55)))" "$(at $((until - 10)))"
    observe 15 900
    check "two suspends: yours, then decaf's" 2 "${#gap_starts[@]}"
    if ((${#gap_starts[@]} >= 2)); then
        check_range "you resumed inside the last minute (s before the deadline)" 5 60 \
            $((until - gap_ends[0] / 1000))
        check_range "decaf suspended at the deadline (ms after it)" -1000 7000 \
            $((gap_starts[1] - until * 1000))
    fi
    confirm "Did 'Suspending soon · At HH:MM' appear right after you resumed?"
fi

# -----------------------------------------------------------------------------
printf '\n'
if ((failures == 0)); then
    echo "All checks passed."
else
    echo "$failures check(s) failed."
    exit 1
fi
