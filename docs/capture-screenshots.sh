#!/usr/bin/env bash
# Captures every Omarchy menu from a running nixarchy VM, for the README.
#
# Run this ON the VM (ssh -p 2222 omarchy@localhost), with the VM started
# against a real display backend:
#
#   QEMU_OPTS="-device virtio-vga-gl -display gtk,gl=on" nix run .#vm
#
# A headless VM does not work. With -display none nothing consumes the
# compositor's frames, page flips never complete, and grim blocks forever --
# the monitor is there and the shell is running, but no screenshot ever
# returns.
set -euo pipefail

out="${1:-$HOME/nixarchy-screenshots}"
mkdir -p "$out"

pid=$(pgrep -f "quickshell -n" | head -1)
[ -n "$pid" ] || {
  echo "the Omarchy shell is not running" >&2
  exit 1
}

# The menu is driven over the shell's IPC, so this needs the session's Wayland
# and Hyprland handles -- which an ssh login does not have.
eval "$(tr '\0' '\n' <"/proc/$pid/environ" |
  grep -E '^(WAYLAND_DISPLAY|XDG_RUNTIME_DIR|HYPRLAND_INSTANCE_SIGNATURE)=' |
  sed 's/^/export /')"

# The only menu IPC is `toggle`, so state has to be observed rather than
# assumed: an earlier version of this script called a `close` method that does
# not exist, and every second capture came out with the menu shut.
menu_open() { hyprctl layers 2>/dev/null | grep -q 'namespace: omarchy-menu'; }

close_menu() {
  menu_open || return 0
  omarchy-shell shell toggle omarchy.menu >/dev/null 2>&1 || true
  sleep 0.8
}

open_menu() { # open_menu <menu-id>
  omarchy-shell shell toggle omarchy.menu "{\"menu\":\"$1\"}" >/dev/null 2>&1 || true
  sleep 1.2
  menu_open && return 0
  # A toggle landed on the wrong phase; try once more.
  omarchy-shell shell toggle omarchy.menu "{\"menu\":\"$1\"}" >/dev/null 2>&1 || true
  sleep 1.2
}

shot() { # shot <file-name> <menu-id>
  local name=$1 menu=$2
  close_menu
  open_menu "$menu"
  if menu_open; then
    grim "$out/$name.png"
    echo "  $name.png"
  else
    echo "  $name.png  SKIPPED (menu would not open)" >&2
  fi
}

echo "capturing to $out"

close_menu
sleep 1.5
grim "$out/00-desktop.png"
echo "  00-desktop.png"

shot 01-menu-root root
shot 02-install install
shot 03-install-service install.service
shot 04-install-editor install.editor
shot 05-install-terminal install.terminal
shot 06-install-browser install.browser
shot 07-install-gaming install.gaming
shot 08-install-ai install.ai
shot 09-remove remove
shot 10-update update
shot 11-learn learn
shot 12-style style
shot 13-setup setup
shot 14-system system

close_menu
echo
echo "done. From the host, copy them into the repo with:"
echo "  scp -P 2222 'omarchy@localhost:$out/*.png' docs/screenshots/"
