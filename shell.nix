{
  mkShell,
  nixd,
  statix,
  deadnix,
  nixfmt-rfc-style,
  nix-tree,
  nix-output-monitor,
  shellcheck,
  qemu,
  jq,
  git,
  gh,
}:
mkShell {
  name = "nixarchy";

  packages = [
    # Nix
    nixd # LSP
    statix # linter
    deadnix # dead code
    nixfmt-rfc-style # formatter
    nix-tree # closure inspection
    nix-output-monitor # readable build output

    # Omarchy is 438 bash scripts; shellcheck is the only tool that helps
    # when a vendored script misbehaves under Nix.
    shellcheck

    qemu # nix run .#vm
    jq
    git
    gh
  ];

  shellHook = ''
    echo "nixarchy dev shell"
    echo
    echo "  nix flake check          verify everything builds"
    echo "  nix build .#omarchy      build the vendored tree only (fast)"
    echo "  nix run .#vm             boot the smoke-test VM"
    echo "  nix fmt                  format"
    echo "  statix check && deadnix  lint"
    echo
  '';
}
