#!/usr/bin/env bash
# run-drivers.sh -- run every headless driver under examples/ and judge it.
#
# The drivers are GDScript SceneTree scripts that attach a .tur script to a
# node and assert on what it did. Nothing ran them but a person, so scripts
# rotted against the prelude and one driver printed a failure followed by
# "all assertions passed". This is the thing CI runs instead.
#
#   GODOT=/path/to/godot tools/run-drivers.sh
#   GODOT=... TUR_BIN=/path/to/tur tools/run-drivers.sh    # also the AOT pass
#
# A driver passes when it exits 0 AND prints no line containing FAIL or
# SCRIPT ERROR. Both halves matter: several drivers report through printerr
# and still exit 0, and a GDScript runtime error does not change the exit
# code at all. Engine-side `ERROR:` lines are not failures on their own --
# the negative tests (typed_signal_bad, reset_and_diag) and a get_node miss
# print them on purpose.
#
# With TUR_BIN set the pong example runs a second time under
# TURMERIC_GODOT_AOT=1, and must also report that ball and paddle dispatched
# through AOT. Without that check a staged library that fails to load falls
# back to the interpreter and the assertions pass anyway -- which is how AOT
# stayed broken on Linux unnoticed.
#
# Needs the extension built into examples/*/bin first (see SConstruct).
set -u

GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PER_DRIVER_TIMEOUT="${TG_DRIVER_TIMEOUT:-180}"

if ! command -v "$GODOT" >/dev/null 2>&1; then
    echo "run-drivers: no Godot at '$GODOT' (set GODOT=/path/to/godot)" >&2
    exit 2
fi

run_with_timeout() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "$PER_DRIVER_TIMEOUT" "$@"
    else
        perl -e 'alarm shift; exec @ARGV' "$PER_DRIVER_TIMEOUT" "$@"
    fi
}

pass=0
fail=0
failed=()
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

# judge NAME EXIT [REQUIRED-SUBSTRING ...] -- reads the driver's output from $log.
judge() {
    local name="$1" rc="$2"; shift 2
    local why=""
    if [ "$rc" -ne 0 ]; then
        why="exit $rc"
    elif grep -qE 'FAIL|SCRIPT ERROR' "$log"; then
        why="printed a failure"
    else
        local need
        for need in "$@"; do
            if ! grep -qF -- "$need" "$log"; then
                why="never printed: $need"
                break
            fi
        done
    fi
    if [ -z "$why" ]; then
        echo "PASS $name"
        pass=$((pass + 1))
    else
        echo "FAIL $name -- $why"
        sed 's/^/    | /' "$log" | grep -vE '^\s+\| \[turmeric-godot\] ' | tail -40
        fail=$((fail + 1))
        failed+=("$name")
    fi
}

# Godot wants a project imported once before `load()` resolves res:// paths.
for proj in spike paddle-pong-tur; do
    run_with_timeout "$GODOT" --headless --path "$ROOT/examples/$proj" --import \
        >/dev/null 2>&1 || true
done

for driver in "$ROOT"/examples/spike/scripts/*.gd; do
    name="spike/$(basename "$driver" .gd)"
    run_with_timeout "$GODOT" --headless --path "$ROOT/examples/spike" \
        --script "scripts/$(basename "$driver")" >"$log" 2>&1
    judge "$name" $?
done

run_with_timeout "$GODOT" --headless --path "$ROOT/examples/paddle-pong-tur" \
    --script scripts/pong_driver.gd >"$log" 2>&1
judge "pong (interpreted)" $?

if [ -n "${TUR_BIN:-}" ]; then
    TURMERIC_GODOT_AOT=1 TUR_BIN="$TUR_BIN" \
        run_with_timeout "$GODOT" --headless --path "$ROOT/examples/paddle-pong-tur" \
        --script scripts/pong_driver.gd >"$log" 2>&1
    judge "pong (AOT)" $? \
        "first dispatch routed via AOT: ball/_process" \
        "first dispatch routed via AOT: paddle/_process"
else
    echo "SKIP pong (AOT) -- TUR_BIN not set"
fi

echo "summary: $pass passed, $fail failed"
if [ "$fail" -ne 0 ]; then
    printf '  failed: %s\n' "${failed[@]}"
    exit 1
fi
