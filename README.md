# nixarchy

[Omarchy](https://omarchy.org) vendored for NixOS.

Omarchy 4.x is not a dotfiles repo — it's an application: **438 shell commands**,
a QuickShell desktop shell, 22 themes, and Hyprland configured through the Lua
API introduced in 0.55. Nixarchy packages that tree as a derivation and patches
the parts that assume Arch, rather than reimplementing it in Nix.

Tracking an upstream release is a source bump, not a re-port.

## Why vendoring

Everything upstream resolves through a single environment variable:

```lua
-- default/hypr/bootstrap.lua
package.path = home.."/.local/state/?.lua;"..home.."/.config/?.lua;"
  ..(os.getenv("OMARCHY_PATH") or "/usr/share/omarchy").."/?.lua;"
```

Point `OMARCHY_PATH` at a store path and the bins, the QML shell, the themes and
the Lua defaults all follow. Only **32 of 438 scripts** touch `pacman`/`yay` —
that's the entire distro-coupling surface.

## Usage

```nix
{
  inputs.nixarchy.url = "github:olafkfreund/nixarchy";

  outputs = { nixpkgs, nixarchy, ... }: {
    nixosConfigurations.mymachine = nixpkgs.lib.nixosSystem {
      modules = [
        nixarchy.nixosModules.nixarchy
        { programs.nixarchy.enable = true; }
      ];
    };
  };
}
```

And in Home Manager:

```nix
{
  imports = [ nixarchy.homeManagerModules.nixarchy ];
  programs.nixarchy.enable = true;
  programs.nixarchy.defaultTheme = "tokyo-night";
}
```

## Try it in a VM

```sh
# graphical -- this is the one that shows the desktop
QEMU_OPTS="-device virtio-vga-gl -display gtk,gl=on" \
  nix run github:olafkfreund/nixarchy#vm

# headless -- boots to a serial console, for reading the journal when the
# graphical session is the thing that is broken
QEMU_OPTS="-display none -serial mon:stdio" \
  nix run github:olafkfreund/nixarchy#vm
```

Autologs in as `omarchy` / `omarchy`.

The display backend is passed at runtime rather than baked into the VM,
because a hardcoded `virtio-vga-gl` makes qemu refuse to start anywhere
without a GL-capable display -- CI, a serial console, an ssh session.

## Development

```sh
nix develop            # or `direnv allow`
nix build .#omarchy    # fast — just the vendored tree
nix flake check        # everything
nix run .#vm           # smoke test (see "Try it in a VM" for QEMU_OPTS)
```

## Design notes

### Bins are symlinked, not wrapped

`bin/omarchy` discovers its subcommands by grepping the first 80 lines of each
sibling script for `# omarchy:summary=` metadata. A `wrapProgram`-generated
wrapper has no such comment, so wrapping every bin makes the CLI report zero
commands *while still building fine*. Runtime dependencies reach the scripts
through the module's `systemPackages` instead. CI asserts on this.

### User state stays mutable

`omarchy-theme-set` applies themes at runtime by copying files into
`~/.local/state/omarchy/current/` and flipping symlinks. That's anti-Nix, and
it's also why theme switching is instant instead of a rebuild.

The split:

- **Nix owns** packages, services, hardware, `OMARCHY_PATH`, the default theme
- **Omarchy owns** `~/.local/state/omarchy` and `~/.config/omarchy` at runtime

The Home Manager module *seeds* these once and never clobbers them. Putting
them under `home.file` would make every theme switch fail.

### Hyprland comes from upstream, not nixpkgs

Omarchy 4.x needs ≥ 0.55 for `hl.bind` / `hl.window_rule` / `hl.on`; nixpkgs is
on 0.54.3.

The flake pins a **commit**, not the `v0.56.2` tag, because that tag does not
build against its own `flake.lock`: its `CMakeLists.txt` asks for
`find_package(glaze 7...<8)` while `nix/overlays.nix` feeds it the glaze 8.0.0
from its locked nixpkgs. `find_package` fails, CMake falls back to cloning glaze
over the network, and the build sandbox has none. Upstream dropped the version
bound after tagging, and `v0.56.2` is the newest tag — so there is no fixed tag
to move to. A commit is just as reproducible; bump it deliberately.

`inputs.nixpkgs.follows` is deliberately **not** set on it — hyprwm asks
consumers not to, and overriding forfeits their binary cache. Keep
`programs.nixarchy.useHyprlandCache` on unless you enjoy compiling a compositor.

## Status

Early.

Verified so far: the vendored tree builds, the `omarchy` CLI resolves all 429 of
its subcommands, the full NixOS closure builds, and the VM boots with Home
Manager activation completing. Whether the QuickShell bar actually renders is
still open -- that needs a graphical boot, not a headless one.

Known gaps:

- `elephant` (walker's backend, 32 call sites) is not in nixpkgs
- The ~31 Omarchy-original packages (`omacut`, `omawrite`, `herdr`, `omarchy-nvim`…)
  are not yet packaged
- `omarchy-pkg-*` and `omarchy-update` still assume pacman; they need stubs
  pointing at `nixos-rebuild`
- The ~40 `install/hardware/*` fixes should mostly defer to
  [nixos-hardware](https://github.com/NixOS/nixos-hardware)

## License

Packaging is MIT. Vendored Omarchy is MIT, © Basecamp.
