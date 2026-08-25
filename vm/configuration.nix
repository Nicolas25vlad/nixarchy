{
  inputs,
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  # Smoke-test VM. The point is to answer one question cheaply: does the
  # QuickShell bar come up against Hyprland's Lua config? Everything here
  # exists to get to a logged-in session fast, not to be a good NixOS host.
  #
  # qemu-vm.nix is imported directly rather than going through
  # `virtualisation.vmVariant`: this configuration is never anything but a VM,
  # and the import is what supplies the root filesystem and bootloader that a
  # bare nixosSystem is missing.
  imports = [ "${modulesPath}/virtualisation/qemu-vm.nix" ];

  programs.nixarchy.enable = true;

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
    description = "Nixarchy smoke test";
    password = "omarchy"; # VM-only; never reachable off the host.
    extraGroups = [
      "wheel"
      "video"
      "input"
      "docker"
      "i2c"
    ];
  };

  # Straight to a session -- a login prompt adds nothing to the smoke test.
  services.displayManager.autoLogin = {
    enable = true;
    user = "omarchy";
  };

  # Software rendering: the VM has no GPU, and wlroots refuses to start
  # without one unless told this is acceptable.
  environment.sessionVariables = {
    WLR_RENDERER_ALLOW_SOFTWARE = "1";
    WLR_NO_HARDWARE_CURSORS = "1";
  };

  virtualisation = {
    memorySize = 8192;
    cores = 4;
    diskSize = 16384;
    qemu.options = [
      "-device virtio-vga-gl"
      "-display gtk,gl=on,show-cursor=on"
    ];
  };

  # Serial console keeps the journal readable from the host when the
  # graphical session is the thing that is broken.
  boot.kernelParams = [ "console=ttyS0" ];

  networking = {
    hostName = "nixarchy-vm";
    firewall.enable = lib.mkForce false;
  };

  environment.systemPackages = with pkgs; [
    kitty
    git
  ];

  system.stateVersion = "25.05";
}
