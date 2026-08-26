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

    # Log in the way a user actually does: through SDDM's greeter. An earlier
    # version autologged in on tty1 and launched Hyprland from the login
    # shell, which exercised the compositor but skipped the greeter entirely
    # -- so SDDM being enabled by this module was never tested at all, and
    # neither was the session file it launches.
    #
    # (Running Hyprland under `su` was tried before that and is worse: no
    # logind session means no seat, and aquamarine dies with
    # `CBackend::create() failed!`. SDDM gives a genuine seat.)

    # plymouth-quit-wait never finishes without a display and blocks the boot.
    boot.plymouth.enable = pkgs.lib.mkForce false;

    # No GPU in the VM, and Hyprland refuses a software renderer unless told.
    # This has to be system-wide now: SDDM starts the session, not a login
    # shell this test controls.
    environment.sessionVariables.WLR_RENDERER_ALLOW_SOFTWARE = "1";

    # No extra GPU device. qemu-vm already gives the machine a display, and
    # machine.screenshot() dumps *that* one -- adding a second sent Hyprland
    # to the new device while the screenshot kept reading the original, which
    # came back pure black and made the wallpaper check fail on a machine
    # whose desktop was fine.

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

  # Reading the greeter means reading pixels: SDDM's Qt greeter puts nothing
  # on a console or in a file that says it is ready for a password.
  enableOCR = true;

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

    # ---- the greeter ---------------------------------------------------
    machine.wait_for_unit("display-manager.service")

    # OCR rather than a unit or a file: what is being asserted is that a human
    # is actually being offered a login, which only the pixels can say.
    # logind knows when the greeter has a seat; OCR does not, and matching on
    # greeter text raced -- wait_for_text returned on a frame the greeter was
    # still painting, the keystrokes went nowhere, and the login never
    # happened.
    machine.wait_until_succeeds("loginctl list-sessions | grep -q greeter")

    # The QML still needs a moment after the session exists before the
    # password field takes input.
    machine.sleep(8)
    machine.screenshot("greeter")

    # A blank greeter would still accept the password and log in, so assert
    # something was actually drawn. This theme OCRs badly -- a few characters
    # is all that comes back -- so the check is "not blank", not the wording.
    drawn = machine.get_screen_text().strip()
    print(f"greeter OCR: {drawn!r}")
    assert drawn, "the greeter drew nothing; a user would see a blank screen"

    # The only user is preselected and the password field has focus.
    machine.send_chars("omarchy\n")

    # The dialog accepting the password is the thing under test; the session
    # starting is the consequence.
    machine.wait_until_succeeds(
        "journalctl -b -u display-manager --no-pager"
        " | grep -q 'Authentication for user .*omarchy.* successful'")

    # ---- session -------------------------------------------------------
    machine.wait_for_unit("user@1000.service")

    # Long enough for omarchy-launch-shell to exhaust its supervision budget:
    # it gives up after 5 relaunches inside one minute.
    machine.sleep(75)

    print("=========== hyprland ===========")
    print(machine.succeed("journalctl -b _UID=1000 -t Hyprland --no-pager || true"))

    print("=========== omarchy-shell ===========")
    print(machine.succeed("journalctl -b -t omarchy-shell --no-pager || true"))

    print("=========== user journal ===========")
    print(machine.succeed("journalctl -b _UID=1000 --no-pager | tail -100 || true"))

    print("=========== is the shell alive? ===========")
    print(machine.succeed("pgrep -a quickshell || echo 'NO QUICKSHELL PROCESS'"))

    # ---- power ----------------------------------------------------------
    # omarchy-powerprofiles-set autodetect reads this exact property, and it
    # reads it as `2>/dev/null` with a fallback: with no UPower the call fails
    # silently and every machine looks like it is on AC forever. So assert the
    # call succeeds, not that a unit is running -- UPower is DBus-activated,
    # so an activatable name is the whole contract.
    onbattery = machine.succeed(
        "busctl get-property org.freedesktop.UPower /org/freedesktop/UPower "
        "org.freedesktop.UPower OnBattery").strip()
    print(f"UPower OnBattery -> {onbattery}")
    assert onbattery.startswith("b "), (
        f"UPower did not answer on DBus (got {onbattery!r}); "
        "omarchy-powerprofiles-set autodetect would silently assume AC.")

    # The VM has no battery, so `false` is the correct answer here. This
    # asserts the channel works, not the value -- a real charge state can only
    # be checked on hardware.
    machine.succeed("powerprofilesctl get")

    # ---- theme reaches GTK ----------------------------------------------
    # The default theme is dark. Everything below is what carries that fact out
    # of Omarchy's own state and into apps it does not own, and every step of it
    # was silently broken: the schemas gsettings writes are installed but were
    # not on XDG_DATA_DIRS, so `gsettings set` was a no-op and a dark desktop
    # came up with light GTK apps and a light Chromium.
    #
    # Nothing is run by hand here on purpose -- login alone must be enough.
    user = ("su omarchy -c 'export XDG_RUNTIME_DIR=/run/user/1000 "
            "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; %s'")

    mode = machine.succeed(
        user % "omarchy-theme-color --file "
               "$HOME/.local/state/omarchy/current/theme/colors.toml mode").strip()
    assert mode == "dark", f"the default theme is not dark any more (got {mode!r})"

    machine.wait_until_succeeds(
        user % "gsettings get org.gnome.desktop.interface color-scheme"
               " | grep -q prefer-dark")

    scheme = machine.succeed(
        user % "gsettings get org.gnome.desktop.interface color-scheme").strip()
    gtk = machine.succeed(
        user % "gsettings get org.gnome.desktop.interface gtk-theme").strip()
    icons = machine.succeed(
        user % "gsettings get org.gnome.desktop.interface icon-theme").strip()
    print(f"color-scheme {scheme} / gtk-theme {gtk} / icon-theme {icons}")

    # "No schemas installed" is what this returned before gsettings-desktop-schemas
    # was reachable, and gsettings exits 0 while saying it.
    assert "prefer-dark" in scheme, f"GTK was not told the theme is dark: {scheme}"

    # Adwaita-dark is not built into GTK 3; it comes from gnome-themes-extra.
    assert "Adwaita-dark" in gtk, f"gtk-theme is {gtk}"
    machine.succeed("test -d /run/current-system/sw/share/themes/Adwaita-dark")

    # Every theme names a Yaru variant, so the name must resolve to a real dir.
    theme_name = icons.strip("'")
    machine.succeed(f"test -d /run/current-system/sw/share/icons/{theme_name}")

    # What Chromium actually reads for BrowserColorScheme "device": 1 is
    # prefer-dark, and 0 -- "no preference" -- is what it read before, which
    # Chromium renders as light.
    portal = machine.succeed(
        user % ("busctl --user call org.freedesktop.portal.Desktop "
                "/org/freedesktop/portal/desktop org.freedesktop.portal.Settings "
                "ReadOne ss org.freedesktop.appearance color-scheme")).strip()
    print(f"portal color-scheme -> {portal}")
    assert portal == "v u 1", (
        f"the settings portal reports {portal!r}, not dark; Chromium and every "
        "other portal-reading app will come up light.")

    # ---- cursor and seeded configs --------------------------------------
    # Omarchy sets a cursor size but no cursor theme, so Hyprland fell back to
    # its own pointer and never followed a theme.
    cursor = machine.succeed(
        user % "gsettings get org.gnome.desktop.interface cursor-theme").strip()
    print(f"cursor-theme {cursor}")
    assert "Bibata" in cursor, f"cursor theme is {cursor}, not Bibata"
    # The dark default theme must get the white half of the pair.
    assert "Ice" in cursor, f"a dark theme should use Bibata-Modern-Ice, got {cursor}"
    machine.succeed(f"test -d /run/current-system/sw/share/icons/{cursor.strip(chr(39))}/cursors")

    # config/ was seeded in full, not just hypr and omarchy. These are the
    # three the manual points users at, and each was missing.
    machine.succeed("test -s /home/omarchy/.config/starship.toml")
    machine.succeed("test -s /home/omarchy/.config/tmux/tmux.conf")
    machine.succeed("test -s /home/omarchy/.config/foot/foot.ini")

    # btop.conf asks for a theme literally named "current"; without the link
    # btop starts with no theme at all.
    machine.succeed("test -L /home/omarchy/.config/btop/themes/current.theme")
    machine.succeed("test -s /home/omarchy/.config/btop/themes/current.theme")

    # btop.theme is rendered from default/themed/*.tpl, and nothing was: the
    # first-run theme-set ran without the package on PATH, so every sibling it
    # calls by bare name was silently not found. foot.ini and gum_env.lua come
    # from the same pass, so they stand in for the rest of it.
    for generated in ["btop.theme", "foot.ini", "gum_env.lua"]:
        machine.succeed(
            f"test -s /home/omarchy/.local/state/omarchy/current/theme/{generated}")


    # ---- compose sequences ----------------------------------------------
    # install/user/xcompose.sh writes ~/.XCompose at first login including a
    # path that upstream owns as /usr/share/omarchy. Getting that wrong is
    # silent: xkbcommon logs a parse failure into the client's stderr and
    # every CapsLock compose sequence in the manual stops working, with
    # nothing on screen to say so.
    machine.succeed("test -s /etc/omarchy/xcompose")
    machine.succeed("grep -q 'Multi_key' /etc/omarchy/xcompose")

    # The include has to resolve from the file the session will actually read.
    included = machine.succeed(
        "sed -n 's/^include \"\\(.*\\)\"$/\\1/p' /home/omarchy/.XCompose"
        " | grep -v '%L' || true").strip()
    print(f"~/.XCompose includes: {included!r}")
    if included:
        machine.succeed(f"test -e {included}")

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
