#!/bin/sh
# Integration test against the running sway session.
# Opens dummy windows (a | (b / c)) on a temporary workspace, toggles b and checks
# that the layout is restored and that the neighbours a and c are never resized.
# Afterwards it returns to the workspace it started on.
cd "$(dirname "$0")"
F=./foolscreen
P=./foolscreen-placeholder
WS=foolscreen-test
logs=$(mktemp -d)
fail=0

has_mark() { swaymsg -t get_marks | jq -e --arg m "$1" 'index($m)' >/dev/null; }
if has_mark _fs_win || has_mark _fs_ph; then
    echo "a window is on the fullscreen workspace, toggle it back first"
    exit 1
fi

# add the for_window rules from README.md until the next reload if the sway config lacks them;
# one command per rule: swaymsg splits at "," and would run the rest on the focused window
config=$(swaymsg -t get_config | jq -r .config)
if ! echo "$config" | grep -qF 'for_window [app_id="^foolscreen-fullscreen$"]'; then
    swaymsg 'for_window [app_id="^foolscreen-fullscreen$"] mark --add _fs_ph' >/dev/null
    swaymsg 'for_window [app_id="^foolscreen-fullscreen$"] move container to workspace fullscreen' >/dev/null
fi
if ! echo "$config" | grep -qF 'for_window [app_id="^foolscreen-float-"]'; then
    swaymsg 'for_window [app_id="^foolscreen-float-"] floating enable' >/dev/null
fi

tree() { swaymsg -t get_tree; }
focused_ws() { swaymsg -t get_workspaces | jq -r '.[] | select(.focused).name'; }
con() { tree | jq -r --arg a "$1" '.. | objects | select(.app_id? == $a) | .'"$2"; }
layout() {
    tree | jq -c --arg ws "$WS" 'def l: if (.nodes | length) > 0 then {(.layout): [.nodes[] | l]} else .app_id end;
        .. | objects | select(.type == "workspace" and .name == $ws) | [.nodes[] | l]'
}
configures() { cat "$logs"/foolscreen-test-a.log "$logs"/foolscreen-test-c.log | grep -c 'xdg_toplevel#[0-9]*\.configure('; }
check() {
    if [ "$2" = "$3" ]; then echo "  PASS $1"; else echo "  FAIL $1: got '$2', expected '$3'"; fail=1; fi
}

spawn() {
    WAYLAND_DEBUG=1 $P "foolscreen-test-$1" "$1" 2>"$logs/foolscreen-test-$1.log" &
    for i in $(seq 100); do [ -n "$(con "foolscreen-test-$1" id)" ] && return; sleep 0.05; done
    echo "dummy window $1 did not appear"; teardown; exit 1
}
setup() {
    swaymsg "workspace $WS" >/dev/null
    spawn a; spawn b; swaymsg splitv >/dev/null; spawn c
    bid=$(con foolscreen-test-b id)
    swaymsg "[con_id=$bid] focus" >/dev/null
    sleep 0.3
    before=$(layout)
    configs=$(configures)
}
# kill only what this test created
teardown() {
    for x in a b c; do
        id=$(con "foolscreen-test-$x" id)
        [ -n "$id" ] && swaymsg "[con_id=$id] kill" >/dev/null
    done
    [ -n "$bid" ] && swaymsg "[app_id=\"^foolscreen-float-$bid\$\"] kill" >/dev/null 2>&1
    swaymsg "workspace \"$orig\"" >/dev/null
    sleep 0.3
}
toggle() {
    if [ "$(tree | jq -r '.. | objects | select(.focused? == true) | .id')" != "$bid" ]; then
        echo "focus is not on the test window, aborting"; teardown; exit 1
    fi
    $F "$1" >/dev/null
    sleep 0.3
}

orig=$(focused_ws)

echo "float: round trip"
setup
toggle float
check "window floats" "$(con foolscreen-test-b type)" floating_con
check "placeholder holds the slot" "$(layout)" "$(echo "$before" | sed "s/foolscreen-test-b/foolscreen-float-$bid/")"
toggle float
check "layout restored" "$(layout)" "$before"
check "neighbours not resized" "$(configures)" "$configs"
teardown

echo "float: placeholder closed"
setup
toggle float
swaymsg "[app_id=\"^foolscreen-float-$bid\$\"] kill" >/dev/null; sleep 0.3
swaymsg "[con_id=$bid] focus" >/dev/null
toggle float
check "window tiled" "$(con foolscreen-test-b type)" con
teardown

echo "fullscreen: round trip"
setup
toggle fullscreen
check "on fullscreen workspace" "$(focused_ws)" fullscreen
check "no border" "$(con foolscreen-test-b border)" none
check "placeholder holds the slot" "$(layout)" "$(echo "$before" | sed 's/foolscreen-test-b/foolscreen-fullscreen/')"
toggle fullscreen
check "back on test workspace" "$(focused_ws)" "$WS"
check "layout restored" "$(layout)" "$before"
check "border restored" "$(con foolscreen-test-b border)" normal
check "neighbours not resized" "$(configures)" "$configs"
teardown

echo "fullscreen: placeholder closed"
setup
toggle fullscreen
swaymsg '[con_mark="^_fs_ph$"] kill' >/dev/null; sleep 0.3
toggle fullscreen
check "back on test workspace" "$(focused_ws)" "$WS"
check "window on test workspace" "$(layout | grep -c foolscreen-test-b)" 1
teardown

echo "fullscreen: window closed"
setup
toggle fullscreen
swaymsg "[con_id=$bid] kill" >/dev/null; sleep 0.3
$F fullscreen >/dev/null; sleep 0.3
check "back on test workspace" "$(focused_ws)" "$WS"
check "placeholder removed" "$(has_mark _fs_ph && echo yes || echo no)" no
check "layout without window" "$(layout)" '["foolscreen-test-a",{"splitv":["foolscreen-test-c"]}]'
teardown

rm -r "$logs"
[ $fail = 0 ] && echo "all tests passed"
exit $fail
