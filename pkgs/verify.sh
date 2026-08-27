#!/usr/bin/env bash
# What a VM cannot tell you. Run this from inside a running Omarchy session.
#
# Everything in this repo's checks runs in a machine with no GPU, no Bluetooth
# radio, no network and no sound. That is enough to catch a great deal -- three
# integration bugs and a first-boot lockout came out of it -- but there is a
# class of question it cannot answer at all:
#
#   does the compositor have hardware acceleration, or is it on llvmpipe?
#   does bluetoothd actually see an adapter?
#   did the RetroArch cores land where RetroArch looks?
#   is the browser tinted, in a browser that is running?
#
# Each check below prints what it found rather than a verdict, because the
# useful output is the value: "llvmpipe" and "AMD Radeon" are both PASS for a
# script and mean opposite things to a person.
set -uo pipefail

bold=$(printf '\033[1m')
dim=$(printf '\033[2m')
red=$(printf '\033[31m')
green=$(printf '\033[32m')
yellow=$(printf '\033[33m')
off=$(printf '\033[0m')

pass=0
fail=0
note=0

ok() {
  printf '  %s✓%s %-34s %s\n' "$green" "$off" "$1" "${2-}"
  pass=$((pass + 1))
}
bad() {
  printf '  %s✗%s %-34s %s\n' "$red" "$off" "$1" "${2-}"
  fail=$((fail + 1))
}
hmm() {
  printf '  %s·%s %-34s %s\n' "$yellow" "$off" "$1" "${2-}"
  note=$((note + 1))
}
head_() { printf '\n%s%s%s\n' "$bold" "$1" "$off"; }

say_dim() { printf '    %s%s%s\n' "$dim" "$1" "$off"; }

printf '\n%snixarchy: what the VM could not check%s\n' "$bold" "$off"
say_dim "Run this inside a running Omarchy session."

# ---- the session ---------------------------------------------------------
head_ "Session"
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  bad "not in a Wayland session" "run this from a terminal inside Omarchy"
  printf '\nNothing below will mean anything. Stopping.\n\n'
  exit 1
fi
ok "Wayland session" "$WAYLAND_DISPLAY"

# `pgrep -x quickshell` first, then read that process's own command line.
#
# Two things make the obvious version wrong. DankMaterialShell is built on
# quickshell as well, so a bare match reports Omarchy's bar as running on a
# machine running somebody else's. And `pgrep -f "quickshell.*omarchy"` also
# matches the shell that invoked this script, because the pattern is sitting
# in that shell's own command line -- which is how it reported a running
# Omarchy bar on a machine with niri on the screen.
omarchy_shell=""
for p in $(pgrep -x quickshell 2>/dev/null); do
  if tr '\0' ' ' <"/proc/$p/cmdline" 2>/dev/null | grep -q omarchy; then
    omarchy_shell=$p
    break
  fi
done

if [ -n "$omarchy_shell" ]; then
  ok "Omarchy shell running" "pid $omarchy_shell"
elif pgrep -x quickshell >/dev/null 2>&1; then
  bad "a quickshell is running, but not Omarchy's" "another shell owns this session"
else
  bad "Omarchy shell not running" "the bar is the thing most likely to be missing"
fi

# ---- graphics ------------------------------------------------------------
# The VM runs llvmpipe, so it can never answer this. On real hardware a
# software renderer means something is wrong with the driver, not the desktop.
head_ "Graphics"
# `|| true` on the whole pipeline, and not merely on hyprctl.
# writeShellApplication runs this under `set -euo pipefail`, so a grep that
# matches nothing fails the pipeline and errexit ends the script -- silently,
# mid-report, which is exactly what it did here: the output stopped after the
# word "Graphics" on a machine with no Hyprland running.
renderer=$(
  {
    timeout 5 hyprctl systeminfo 2>/dev/null |
      grep -iE "GPU information|Renderer" |
      head -2 |
      tr '\n' ' '
  } || true
)
if [ -n "$renderer" ]; then
  case "$renderer" in
    *llvmpipe* | *softpipe* | *swrast*)
      bad "software rendering" "the driver is not being used"
      say_dim "$renderer"
      ;;
    *)
      ok "hardware rendering" ""
      say_dim "$renderer"
      ;;
  esac
else
  hmm "could not read the renderer" "hyprctl systeminfo said nothing"
fi

# ---- bluetooth -----------------------------------------------------------
# The checks assert the service is enabled and that the VM has no radio. This
# is the other half.
head_ "Bluetooth"
if [ ! -d /sys/class/bluetooth ] || [ -z "$(ls -A /sys/class/bluetooth 2>/dev/null)" ]; then
  hmm "no adapter on this machine" "nothing to test"
elif ! systemctl is-active bluetooth.service >/dev/null 2>&1; then
  bad "adapter present, bluetoothd not running" "the bar widget will be inert"
else
  adapters=$(timeout 5 bluetoothctl list 2>/dev/null | wc -l)
  if [ "$adapters" -gt 0 ]; then
    ok "bluetoothd sees $adapters adapter(s)" ""
    say_dim "$(timeout 5 bluetoothctl list 2>/dev/null | head -1)"
  else
    bad "bluetoothd running but sees no adapter" ""
  fi
fi

# ---- theming -------------------------------------------------------------
head_ "Theme"
scheme=$(
  timeout 5 busctl --user call org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
    org.freedesktop.portal.Settings ReadOne ss org.freedesktop.appearance color-scheme 2>/dev/null
)
case "$scheme" in
  *"u 1"*) ok "portal reports dark" "Chromium and GTK follow this" ;;
  *"u 2"*) ok "portal reports light" "" ;;
  *"u 0"*) bad "portal reports no preference" "browsers will come up light" ;;
  *) hmm "portal did not answer" "${scheme:-nothing}" ;;
esac

cursor=$(timeout 5 gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")
case "$cursor" in
  Bibata*) ok "cursor follows the theme" "$cursor" ;;
  "" | Adwaita) bad "cursor is the default" "${cursor:-unset}; Omarchy's theme hook did not run" ;;
  *) hmm "cursor is something else" "$cursor" ;;
esac

policy=/etc/chromium/policies/managed/color.json
if [ -f $policy ]; then
  ok "browser accent written" "$( (grep -o '#[0-9a-fA-F]\{6\}' "$policy" | head -1) || true)"
else
  hmm "browser accent not set" "programs.nixarchy.browserThemeUser is off"
fi

# ---- the shell -----------------------------------------------------------
head_ "Shell"
if type tdl >/dev/null 2>&1 || command -v tdl >/dev/null 2>&1; then
  ok "Omarchy's functions are here" "in ${SHELL##*/}"
else
  bad "Omarchy's functions are missing" "in ${SHELL##*/}"
  say_dim "bash, zsh and fish are covered; anything else is not"
fi

compose=$( { sed -n 's/^include "\(.*\)"$/\1/p' "$HOME/.XCompose" 2>/dev/null |
  grep -v '%L' | head -1; } || true)
if [ -n "$compose" ] && [ -e "$compose" ]; then
  ok "compose sequences resolve" "$compose"
elif [ -n "$compose" ]; then
  bad "$HOME/.XCompose points at nothing" "$compose"
else
  hmm "no $HOME/.XCompose" "first login may not have run yet"
fi

# ---- things with big closures the VM never launches ----------------------
head_ "Installed and launchable"
cores=$(timeout 5 omarchy-retroarch-cores 2>/dev/null || true)
if [ -n "$cores" ] && [ -d "$cores" ]; then
  ok "RetroArch cores" "$( (find "$cores" -name '*_libretro.so' | wc -l) || echo 0) cores in $cores"
else
  hmm "RetroArch not installed" "enable apps.retroarch to test this"
fi

for app in nautilus pinta gnome-disks xournalpp; do
  if command -v "$app" >/dev/null 2>&1; then
    ok "$app" "on PATH"
  else
    hmm "$app" "not installed"
  fi
done

# ---- summary -------------------------------------------------------------
printf '\n%s%s passed, %s failed, %s worth a look%s\n' \
  "$bold" "$pass" "$fail" "$note" "$off"
if [ "$fail" -gt 0 ]; then
  printf '%sA failure here is a real one: everything above is something a VM\n' "$dim"
  printf 'cannot check, so nothing in CI would have caught it.%s\n\n' "$off"
  exit 1
fi
printf '\n'
