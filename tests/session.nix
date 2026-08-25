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

    programs.nixarchy.enable = true;

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
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
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
  '';
}
