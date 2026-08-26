#!/usr/bin/env bash
# What to change before adding nixarchy to a machine you already run.
#
# Reads the running system and prints the configuration it would need. Changes
# nothing: every conflict nixarchy can cause is an evaluation failure, so the
# cost of finding out the hard way is a failed rebuild rather than a broken
# machine -- but a failed rebuild with five errors in it is a bad first
# impression, and they are all knowable in advance.
#
# Deliberately inspects the live system rather than evaluating a flake: this
# has to be useful *before* nixarchy is an input, and `nix run` on a flake that
# is not yet imported anywhere is the only entry point a new user has.
set -uo pipefail

sw=/run/current-system/sw
sessions=$sw/share/wayland-sessions
config_home=${XDG_CONFIG_HOME:-$HOME/.config}

bold=$(printf '\033[1m')
dim=$(printf '\033[2m')
warn=$(printf '\033[33m')
ok=$(printf '\033[32m')
off=$(printf '\033[0m')

say() { printf '%s\n' "$*"; }
finding() { printf '  %s%s%s %s\n' "$2" "$1" "$off" "$3"; }

# Every line that has to go into their configuration, collected as we go and
# printed together at the end -- a snippet to paste beats a list of prose
# instructions to translate.
declare -a snippet=()
declare -a notes=()

say ""
say "${bold}nixarchy: what this machine needs${off}"
say "${dim}Reading the running system. Nothing is modified.${off}"
say ""

# ---- Hyprland ------------------------------------------------------------
# programs.hyprland.package is the one option nixarchy sets outright rather
# than with mkDefault: nixpkgs defines it at mkDefault priority, so matching
# that ties instead of yielding. Anyone who already sets it therefore collides.
say "${bold}Compositor${off}"
if [ -e "$sessions/hyprland.desktop" ]; then
  hypr_bin=$(sed -n 's/^Exec=//p' "$sessions/hyprland.desktop" | awk '{print $1}')
  hypr_ver=$("${hypr_bin%/*}/Hyprland" --version 2>/dev/null |
    grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  finding "Hyprland already configured" "$warn" "(${hypr_ver:-unknown version})"
  say "     nixarchy pins its own Hyprland and does not defer, so this collides."
  snippet+=(
    "  # You already set programs.hyprland.package; nixarchy sets it too, and"
    "  # neither defers. Keep yours -- anything from 0.55 satisfies nixarchy."
    "  programs.hyprland.package = lib.mkForce pkgs.hyprland;"
    "  programs.hyprland.portalPackage = lib.mkForce pkgs.xdg-desktop-portal-hyprland;"
  )
  case "$hypr_ver" in
    "" ) notes+=("Could not read your Hyprland version; nixarchy needs >= 0.55.") ;;
    0.5[0-4]* | 0.[0-4]* )
      notes+=("Your Hyprland ${hypr_ver} is older than the 0.55 Lua API Omarchy is written against. Nixarchy will refuse to evaluate until you move up, or drop the mkForce and take its pin.") ;;
  esac
else
  finding "No Hyprland yet" "$ok" "nixarchy brings its own"
fi
say ""

# ---- the greeter ---------------------------------------------------------
say "${bold}Display manager${off}"
found_dm=""
for dm in gdm sddm lightdm greetd ly; do
  if systemctl is-enabled "$dm.service" >/dev/null 2>&1 ||
    systemctl is-active "$dm.service" >/dev/null 2>&1; then
    found_dm=$dm
    break
  fi
done
if [ -n "$found_dm" ] && [ "$found_dm" != sddm ]; then
  finding "$found_dm is greeting" "$warn" ""
  say "     Two display managers is not a working configuration."
  snippet+=(
    "  # $found_dm already greets; nixarchy's SDDM would be a second one."
    "  # Your greeter picks up the \"Omarchy\" session from wayland-sessions."
    "  programs.nixarchy.displayManager = false;"
  )
elif [ "$found_dm" = sddm ]; then
  finding "SDDM is greeting" "$ok" "nixarchy themes it"
else
  finding "No display manager" "$ok" "nixarchy enables SDDM"
fi
say ""

# ---- the Hyprland config -------------------------------------------------
# The seed never overwrites a file the user owns, so an existing hyprland.lua
# is kept and Omarchy's is not installed. The session entry is what makes that
# survivable, and it is on by default -- this is here to say so, because the
# failure it prevents is silent.
say "${bold}Hyprland config${off}"
if [ -e "$config_home/hypr/hyprland.lua" ]; then
  if [ -L "$config_home/hypr/hyprland.lua" ]; then
    finding "$config_home/hypr/hyprland.lua is managed" "$warn" "(a symlink -- home-manager, probably)"
  else
    finding "$config_home/hypr/hyprland.lua exists" "$warn" "(your own file)"
  fi
  say "     nixarchy will not overwrite it, so Omarchy's own config is not"
  say "     installed. Log in through the ${bold}Omarchy${off} session instead: it runs"
  say "     Hyprland against Omarchy's config with --config and needs no file"
  say "     of yours. It is registered by default."
  notes+=("Both sessions share ~/.config/hypr/{monitors,input,bindings,looknfeel,autostart}.lua. Omarchy's bootstrap builds Hyprland's Lua module path from \$HOME/.config and nothing else, so only the entry point differs. Editing those changes both.")
else
  finding "No Hyprland config" "$ok" "Omarchy's is installed as-is"
fi
say ""

# ---- things nixarchy defers on -------------------------------------------
say "${bold}Services${off}"
if systemctl is-enabled tlp.service >/dev/null 2>&1; then
  finding "TLP is managing power" "$warn" ""
  say "     nixarchy leaves power-profiles-daemon off; NixOS forbids both."
  say "     ${dim}omarchy powerprofiles stops working. Nothing else does.${off}"
else
  finding "No TLP" "$ok" "power-profiles-daemon is enabled"
fi

if systemctl is-active pulseaudio.service >/dev/null 2>&1 ||
  systemctl --user is-active pulseaudio.service >/dev/null 2>&1; then
  finding "PulseAudio is the sound server" "$warn" ""
  say "     ${bold}This one nixarchy cannot fix.${off} NixOS enables PipeWire for any"
  say "     graphical session and asserts the two conflict -- a bare"
  say "     programs.hyprland.enable fails the same way. Move to PipeWire"
  say "     first, or nixarchy will not evaluate."
else
  finding "PipeWire" "$ok" ""
fi

# Unit names as systemd spells them, not lowercased: NetworkManager.service is
# capitalised, and lowercasing it returned not-found -- which this reported as
# "NetworkManager is off here" on a machine where it was enabled.
for unit in docker.service NetworkManager.service; do
  if ! systemctl is-enabled "$unit" >/dev/null 2>&1; then
    say "  ${dim}${unit%.service} is off here; nixarchy defaults it on but defers to you.${off}"
  fi
done
say ""

# ---- the snippet ---------------------------------------------------------
say "${bold}Add this to your configuration${off}"
say ""
say "  programs.nixarchy.enable = true;"
if [ ${#snippet[@]} -gt 0 ]; then
  printf '%s\n' "${snippet[@]}"
fi
say ""
say "  ${dim}# and, for the user who will run the desktop:${off}"
say "  home-manager.users.<you> = {"
say "    imports = [ inputs.nixarchy.homeManagerModules.nixarchy ];"
say "    programs.nixarchy.enable = true;"
say "  };"
say ""

if [ ${#notes[@]} -gt 0 ]; then
  say "${bold}Worth knowing${off}"
  for n in "${notes[@]}"; do
    say "  - $n"
  done
  say ""
fi

say "${dim}Nixarchy also adds two binary caches. Without them, enabling it means"
say "compiling a compositor. programs.nixarchy.binaryCaches = false to decline.${off}"
say ""
