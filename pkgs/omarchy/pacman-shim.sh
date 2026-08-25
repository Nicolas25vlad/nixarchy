#!/usr/bin/env bash

# NixOS has no pacman, and ~15 of Omarchy's 430 bins still shell out to it --
# the ones managing Arch release channels, keyrings, orphan pruning and the
# Quattro migration. Rewriting all of them for Nix would be rewriting things
# that have no Nix meaning: the flake input IS the release channel, and the
# store has no orphans to prune.
#
# So they fail. This only decides HOW. Without it the failure is
# `pacman: command not found`, which reads like a broken install; with it the
# user gets told what replaced the command.
#
# Deliberately keeps pacman's contract: message on stderr, non-zero exit. The
# bins that query pacman for display -- omarchy version, omarchy debug --
# already wrap it in `2>/dev/null || fallback` and keep working unchanged.
cat >&2 <<EOF
pacman is not how NixOS installs software.

  omarchy pkg install <app>   works: it edits ~/.config/nixarchy/apps.nix
  omarchy update              works: it rebuilds from your flake
  nixarchy-apply              applies pending changes

Anything else pacman did here -- release channels, keyrings, orphan pruning --
is your flake's job now: edit flake.nix, then \`nix flake update\`.
EOF
exit 1
