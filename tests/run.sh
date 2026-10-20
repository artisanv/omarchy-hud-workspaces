#!/usr/bin/env bash
# Tests for HUD Workspaces: syntax/lint, ws-step order logic (mirrors
# computeWorkspaceIds() in Workspaces.qml), ws-room room validation,
# ws-setup install/remove on a copy of a Hyprland config, ws-settings
# import validation. Nothing here touches the real config or Hyprland.
#
#   tests/run.sh            run everything; exit 1 on any failure

here=$(cd "$(dirname "$0")" && pwd)
src=$here/..
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export XDG_STATE_HOME=$tmp/state
pass=0 fail=0

ok() { pass=$((pass + 1)); printf '  ok  %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [[ -n ${2:-} ]] && printf '       %s\n' "$2"; }
eq() { [[ $2 == "$3" ]] && ok "$1" || bad "$1" "expected [$3], got [$2]"; }

echo "syntax"
for s in ws-step ws-room ws-setup ws-settings; do
  bash -n "$src/$s" && ok "bash -n $s" || bad "bash -n $s"
done
if command -v shellcheck >/dev/null; then
  for s in ws-step ws-room ws-setup ws-settings; do
    shellcheck -S error "$src/$s" >/dev/null && ok "shellcheck $s" || bad "shellcheck $s"
  done
else
  echo "  (shellcheck not installed, skipped)"
fi
if [[ -x /usr/lib/qt6/bin/qmllint ]]; then
  for q in Workspaces.qml DropIndicator.qml; do
    /usr/lib/qt6/bin/qmllint "$src/$q" 2>&1 | grep -q '\[syntax\]' && bad "qmllint $q" || ok "qmllint $q (syntax)"
  done
fi
grep -q IpcHandler "$src/Workspaces.qml" && bad "no test IpcHandler left in Workspaces.qml" || ok "no test IpcHandler left in Workspaces.qml"
v_manifest=$(jq -r .version "$src/manifest.json")
grep -q "Version $v_manifest" "$src/README.md" && ok "README version matches manifest ($v_manifest)" ||
  bad "README version matches manifest" "manifest $v_manifest"
eq "manifest id" "$(jq -r .id "$src/manifest.json")" swordfish.workspaces

echo "ws-step order"
order() { HUD_TEST_ENTRY=$1 HUD_TEST_LIVE=$2 "$src/ws-step" order; }
eq "default"                         "$(order '{}' '[1]')" "1 2 3 4 5"
eq "saved order first"               "$(order '{"order":"[3,1,2]"}' '[1]')" "3 1 2 4 5"
eq "order as a real array"           "$(order '{"order":[5,4]}' '[]')" "5 4 1 2 3"
eq "ids above 5 only while live"     "$(order '{"order":"[8,9,1]"}' '[1,8]')" "8 1 2 3 4 5"
eq "other live ws appended in order" "$(order '{}' '[7,6,1]')" "1 2 3 4 5 6 7"
eq "deleted hidden unless live"      "$(order '{"hidden":"[2,3]"}' '[3]')" "1 3 4 5"
eq "junk in order ignored"           "$(order '{"order":"[\"x\",0,11,2.5,2,2]"}' '[]')" "2 1 3 4 5"
eq "broken JSON order"               "$(order '{"order":"[1,"}' '[]')" "1 2 3 4 5"

echo "ws-room check"
check() { "$src/ws-room" check "$1"; }
eq "argv kept, quoted"        "$(check '[{"argv":["gnome-terminal","--working-directory=/tmp/a b"]}]')" 'gnome-terminal --working-directory=/tmp/a\ b'
eq "legacy cmd split"         "$(check '[{"cmd":"gnome-terminal --working-directory=/tmp/a\\ b"}]')" 'gnome-terminal --working-directory=/tmp/a\ b'
eq "shell syntax not run"     "$(check '[{"cmd":"$(touch '"$tmp"'/pwned)"}]')" skip
[[ -e $tmp/pwned ]] && bad "command substitution did not run" || ok "command substitution did not run"
eq "metacharacters stay data" "$(check '[{"argv":["sh","-c;","x"]}]')" 'sh -c\; x'
eq "missing program"          "$(check '[{"argv":["/nonexistent/prog"]}]')" skip
eq "flatpak id allowlisted"   "$(check '[{"argv":["flatpak","run","com.x;rm"]}]')" skip
eq "flatpak extra args"       "$(check '[{"argv":["flatpak","run","--command=sh","org.x"]}]')" skip
eq "argv not a list"          "$(check '[{"argv":"bash"}]')" skip
eq "empty argv element"       "$(check '[{"argv":["bash",""]}]')" skip
eq "room not a list"          "$(check '{"a":1}')" "not a list"

echo "ws-setup (on a copy)"
cfg=$tmp/cfg
mkdir -p "$cfg/hypr" "$cfg/omarchy"
cat >"$cfg/hypr/hyprland.lua" <<'EOF'
require("hypr.input")
require("hypr.bindings")
-- personal config
EOF
cat >"$cfg/hypr/input.lua" <<'EOF'
-- Enable touchpad gestures for changing workspaces.
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
EOF
echo '-- my binds' >"$cfg/hypr/bindings.lua"
cp -r "$cfg/hypr" "$tmp/orig"
setup() { XDG_CONFIG_HOME=$cfg HUD_SETUP_NO_RELOAD=1 "$src/ws-setup" "$@"; }
st() { setup status | jq -r "$1"; }
eq "starts not installed"         "$(st .installed)" false
setup install --quiet
eq "installed"                    "$(st .ok)" true
eq "stock swipe off"              "$(st .stockSwipe)" false
eq "drop on by default"           "$(st .drop)" true
command -v luac >/dev/null && { luac -p "$cfg/hypr/hud_workspaces.lua" && ok "generated Lua parses" || bad "generated Lua parses"; }
setup install --quiet
eq "idempotent loader"            "$(grep -c 'managed by ws-setup' "$cfg/hypr/hyprland.lua")" 1
setup install --no-drop --quiet
eq "drop off"                     "$(st .drop)" false
[[ -e $cfg/omarchy/hooks/post-update.d/hud-workspaces.hook ]] && bad "no hook unless asked" || ok "no hook unless asked"
setup install --auto-reapply --quiet
[[ -x $cfg/omarchy/hooks/post-update.d/hud-workspaces.hook ]] && ok "hook with --auto-reapply" || bad "hook with --auto-reapply"
echo '-- an update rewrote this' >"$cfg/hypr/hud_workspaces.lua"
eq "detects a changed file"       "$(st .ok)" false
setup reapply --quiet
eq "reapply restores it"          "$(st .ok)" true
setup remove --quiet
diff -q "$tmp/orig/hyprland.lua" "$cfg/hypr/hyprland.lua" >/dev/null && ok "remove: hyprland.lua as before" || bad "remove: hyprland.lua as before" "$(diff "$tmp/orig/hyprland.lua" "$cfg/hypr/hyprland.lua")"
diff -q "$tmp/orig/input.lua" "$cfg/hypr/input.lua" >/dev/null && ok "remove: input.lua as before" || bad "remove: input.lua as before" "$(diff "$tmp/orig/input.lua" "$cfg/hypr/input.lua")"
[[ -e $cfg/hypr/hud_workspaces.lua || -e $cfg/omarchy/hooks/post-update.d/hud-workspaces.hook ]] &&
  bad "remove: files gone" || ok "remove: files gone"
# Legacy README snippet is migrated.
cat >>"$cfg/hypr/bindings.lua" <<'EOF'
-- HUD Workspaces: Super+<number> follows the bar order (the n-th card), not the
local hud_ws_step = os.getenv("HOME") .. "/.config/omarchy/plugins/swordfish.workspaces/ws-step"
for n = 1, 10 do
  o.bind("SUPER + x", "y", hud_ws_step .. " slot " .. n)
end
EOF
eq "legacy detected"              "$(st .legacy)" true
setup install --quiet
eq "legacy migrated"              "$(st .legacy)/$(st .ok)" false/true
eq "rest of bindings.lua kept"    "$(cat "$cfg/hypr/bindings.lua")" "-- my binds"

echo "ws-settings import validation"
eq "rejects a non-object" "$("$src/ws-settings" import <(echo '[1]') 2>&1 | head -c 30)" "Not a HUD Workspaces settings "

# Import writes shell.json itself: known keys only, types checked, JSON kept
# as text, file stays private.
scfg=$tmp/scfg
mkdir -p "$scfg/omarchy"
echo '{"bar":{"layout":{"left":[{"id":"swordfish.workspaces","order":"[1,2]"}],"center":[],"right":[]}}}' >"$scfg/omarchy/shell.json"
chmod 600 "$scfg/omarchy/shell.json"
ws_settings() { XDG_CONFIG_HOME=$scfg XDG_STATE_HOME=$tmp/state "$src/ws-settings" "$@"; }
echo '{"rooms":[{"name":"A","apps":[]}],"profiles":"[{\"name\":\"P\",\"rooms\":[]}]","wrapSwipe":"yes","evil":1,"transitionDuration":600}' >"$tmp/imp.json"
ws_settings import "$tmp/imp.json" >/dev/null
e=$(jq -c '.bar.layout.left[0]' "$scfg/omarchy/shell.json")
eq "import: rooms stored as text"   "$(jq -r '.rooms | type' <<<"$e")" string
eq "import: profiles kept"          "$(jq -r '.profiles | fromjson | .[0].name' <<<"$e")" P
eq "import: wrong type dropped"     "$(jq -r 'has("wrapSwipe")' <<<"$e")" false
eq "import: unknown key dropped"    "$(jq -r 'has("evil")' <<<"$e")" false
eq "import: number kept"            "$(jq -r '.transitionDuration' <<<"$e")" 600
eq "import: other keys kept"        "$(jq -r '.order' <<<"$e")" "[1,2]"
eq "import: shell.json still 600"   "$(stat -c %a "$scfg/omarchy/shell.json")" 600
echo '{"hidden":"[3]"}' | ws_settings apply
eq "apply: reads stdin"             "$(jq -r '.bar.layout.left[0].hidden' "$scfg/omarchy/shell.json")" "[3]"
mkdir -p "$scfg/omarchy/hud-workspaces/backups"; chmod 755 "$scfg/omarchy/hud-workspaces/backups"
touch "$scfg/omarchy/hud-workspaces/backups/2026-01-01.json"; chmod 644 "$scfg/omarchy/hud-workspaces/backups/2026-01-01.json"
ws_settings backup
eq "backup: folder private"         "$(stat -c %a "$scfg/omarchy/hud-workspaces/backups")" 700
eq "backup: files private"          "$(stat -c %a "$scfg/omarchy/hud-workspaces/backups"/*.json | sort -u | tr '\n' ' ')" "600 "

echo "no stored data on command lines"
for f in ws-room ws-settings; do
  grep -qE 'omarchy bar set|hyprctl eval' "$src/$f" && bad "$f: no omarchy bar set / hyprctl eval" || ok "$f: no omarchy bar set / hyprctl eval"
done
grep -q '"omarchy bar set ' "$src/Workspaces.qml" && bad "widget: writes settings in the shell" || ok "widget: writes settings in the shell"
grep -qE 'roomScript, "launch(-deck)?", String|JSON.stringify\(deck\)\]' "$src/Workspaces.qml" &&
  bad "widget: rooms launched via stdin" || ok "widget: rooms launched via stdin"
eq "check: reads stdin"             "$(echo '[{"argv":["ls","-la"]}]' | "$src/ws-room" check -)" "ls -la"

echo
echo "$pass passed, $fail failed"
(( fail == 0 ))
