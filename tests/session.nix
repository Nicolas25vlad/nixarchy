{ inputs, pkgs }:
# Drives a real Omarchy session and reports what it logged.
#
# This exists because the failure that matters -- "the panel shows for a few
# seconds then dies" -- leaves its reason in a *user* journal that nobody can
# reach without logging in, and the session that would let you log in is the
# broken thing. Reading it over a serial console does not work either: once a
# GPU device is present the kernel moves its console to tty0 and the serial
# log ends at the login prompt.
#
# No GPU is needed. Hyprland always registers the headless aquamarine backend
# as MANDATORY and only adds DRM if available (src/Compositor.cpp), so the
# compositor comes up on a machine with no display hardware whatsoever.
pkgs.testers.runNixOSTest {
  name = "nixarchy-session";

  nodes.machine = {
    imports = [
      inputs.self.nixosModules.nixarchy
      inputs.home-manager.nixosModules.home-manager
    ];

    programs.nixarchy = {
      enable = true;
      # Somewhere real for nixarchy-apply to copy the selection into. The VM
      # in vm/configuration.nix builds a full flake there; this test only
      # needs the copy to have a destination.
      flake = "/etc/nixos";
    };

    # Start the session the way a real login does. An earlier version ran
    # Hyprland under `su`, which has no logind session and therefore no seat,
    # and aquamarine died with `CBackend::create() failed!` -- a property of
    # the harness, not of the thing under test. Autologin on tty1 gives a
    # genuine seat.
    services.getty.autologinUser = "omarchy";

    # plymouth-quit-wait never finishes without a display and blocks the boot.
    boot.plymouth.enable = pkgs.lib.mkForce false;
    services.displayManager.sddm.enable = pkgs.lib.mkForce false;

    # A GPU so the DRM backend is available, as it is on a real machine.
    virtualisation.qemu.options = [ "-device virtio-gpu-pci" ];

    # Launch Hyprland from the autologin shell, which is where the seat is.
    programs.bash.loginShellInit = ''
      if [ "$(tty)" = "/dev/tty1" ]; then
        export WLR_RENDERER_ALLOW_SOFTWARE=1
        export XDG_RUNTIME_DIR=/run/user/$(id -u)
        Hyprland > /tmp/hyprland.log 2>&1
      fi
    '';

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      sharedModules = [ inputs.self.homeManagerModules.nixarchy ];
      users.omarchy = {
        programs.nixarchy.enable = true;
        home.stateVersion = "25.05";
      };
    };

    users.users.omarchy = {
      isNormalUser = true;
      uid = 1000;
      password = "omarchy";
      extraGroups = [
        "wheel"
        "video"
        "input"
      ];
    };

    virtualisation = {
      memorySize = 6144;
      cores = 4;
    };

    system.activationScripts.testFlakeDir = ''
      mkdir -p /etc/nixos
      chmod 0777 /etc/nixos
    '';
  };

  testScript = ''
    import os
    machine.wait_for_unit("multi-user.target")

    # ---- app selection -------------------------------------------------
    # Deliberately before anything graphical: Home Manager seeds apps.nix at
    # system activation, so none of this needs a session, and a slow login
    # must not be able to mask a broken selection loop.
    machine.wait_for_file("/home/omarchy/.config/nixarchy/apps.nix")
    machine.succeed("su omarchy -c 'nixarchy-app-enable brave'")
    machine.succeed("su omarchy -c 'nixarchy-app-enable helix'")
    enabled = machine.succeed(
        "grep -E '^[[:space:]]*[a-z0-9_-]+\\.enable' /home/omarchy/.config/nixarchy/apps.nix"
    )
    print(enabled)
    assert "brave.enable" in enabled, "brave was not enabled"
    assert "helix.enable" in enabled, "helix was not enabled"
    # A pick that leaves the file unparseable would break the next rebuild.
    machine.succeed("nix-instantiate --parse /home/omarchy/.config/nixarchy/apps.nix >/dev/null")

    # Picking the same app twice must be a no-op, not a second uncomment.
    machine.succeed("su omarchy -c 'nixarchy-app-enable brave'")
    machine.succeed("nix-instantiate --parse /home/omarchy/.config/nixarchy/apps.nix >/dev/null")

    # Answering "no" to the prompt asserts the copy, not a full rebuild.
    print(machine.succeed("su omarchy -c 'echo n | nixarchy-apply' 2>&1"))
    machine.succeed("grep -q 'brave.enable' /etc/nixos/nixarchy-apps.nix")
    print("selection reached /etc/nixos/nixarchy-apps.nix")

    # ---- session -------------------------------------------------------
    # Autologin on tty1 starts Hyprland from a real seat.
    machine.wait_for_unit("user@1000.service")

    # Long enough for omarchy-launch-shell to exhaust its supervision budget:
    # it gives up after 5 relaunches inside one minute.
    machine.sleep(75)

    print("=========== hyprland ===========")
    print(machine.succeed("cat /tmp/hyprland.log || true"))

    print("=========== omarchy-shell ===========")
    print(machine.succeed("journalctl -b -t omarchy-shell --no-pager || true"))

    print("=========== user journal ===========")
    print(machine.succeed("journalctl -b _UID=1000 --no-pager | tail -100 || true"))

    print("=========== is the shell alive? ===========")
    print(machine.succeed("pgrep -a quickshell || echo 'NO QUICKSHELL PROCESS'"))

    # ---- does the wallpaper actually render? ----------------------------
    # Everything else here proves the tree assembles. This proves the desktop
    # is not black -- which every other check passed while it was.
    #
    # machine.screenshot() goes through qemu's own screendump rather than a
    # compositor screencopy, so it works with no display backend; `grim`
    # blocks forever in that situation because nothing consumes the frames.
    import subprocess

    def avg(path):
        out = subprocess.run(
            ["${pkgs.imagemagick}/bin/magick", path, "-resize", "1x1", "-format", "%[hex:u]", "info:"],
            capture_output=True, text=True, check=True)
        return tuple(int(out.stdout.strip()[i:i + 2], 16) for i in (0, 2, 4))

    machine.wait_until_succeeds("test -s $(readlink -f /home/omarchy/.local/state/omarchy/current/background)")
    machine.sleep(5)
    machine.screenshot("desktop")
    shot = os.path.join(os.environ["out"], "desktop.png")
    paper = machine.succeed(
        "readlink -f /home/omarchy/.local/state/omarchy/current/background").strip()
    machine.copy_from_machine(paper, "")
    local_paper = os.path.join(os.environ["out"], os.path.basename(paper))

    s_r, s_g, s_b = avg(shot)
    w_r, w_g, w_b = avg(local_paper)
    print(f"screen    #{s_r:02X}{s_g:02X}{s_b:02X}")
    print(f"wallpaper #{w_r:02X}{w_g:02X}{w_b:02X}")

    # A wallpaper that never became a texture leaves the theme background --
    # near-black, and nothing like the image. Tolerance is wide on purpose:
    # the bar and any toast tint the average, and the point is to catch black,
    # not to grade colour accuracy.
    delta = abs(s_r - w_r) + abs(s_g - w_g) + abs(s_b - w_b)
    assert delta < 120, (
        f"the desktop does not look like its wallpaper (delta {delta}). "
        "A wallpaper wider than GL_MAX_TEXTURE_SIZE renders as nothing at all, "
        "with Qt still reporting the image Ready -- see the sourceSize cap in "
        "pkgs/omarchy/default.nix.")
    print(f"wallpaper renders (delta {delta})")

  '';
}
