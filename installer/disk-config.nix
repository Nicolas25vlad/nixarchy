# The disk layouts the installer offers. Imported by the installed system too,
# so the layout is declared once and is what `fileSystems` derives from --
# epic invariant 1 applied to the disk: text in the user's flake, not a side
# effect of an install script.
#
# `mode = "whole"` owns the whole disk. `mode = "free"` describes only the two
# partitions that the installer created imperatively in an existing GPT table.
# The free-space shape deliberately has no `gpt` layer: disko's GPT type uses
# positional partition numbers and can relabel an existing partition when a
# number is already occupied. Re-running the free-space config on a wiped disk
# will not recreate its partition table; that is intentional and safe.
{
  device,
  encrypt ? true,
  mode ? "whole",
}:
let
  # Omarchy's layout on Arch is @ @home @log and @pkg for pacman's cache.
  # @nix replaces @pkg: the store is the thing worth its own subvolume here,
  # and there is no package cache to keep.
  mountOptions = [
    "compress=zstd"
    "noatime"
  ];

  btrfs = {
    type = "btrfs";
    extraArgs = [ "-f" ];
    subvolumes = {
      "@" = {
        mountpoint = "/";
        inherit mountOptions;
      };
      "@home" = {
        mountpoint = "/home";
        inherit mountOptions;
      };
      "@nix" = {
        mountpoint = "/nix";
        inherit mountOptions;
      };
      "@log" = {
        mountpoint = "/var/log";
        inherit mountOptions;
      };

      # Where snapper keeps snapshots, and it has to exist before snapper can
      # take one: NixOS' snapper module does not create `.snapshots` itself
      # (nixpkgs#34595; the fix, PR #368449, is still unmerged), so a machine
      # without these subvolumes has a configured snapper that silently takes
      # nothing.
      #
      # Separate subvolumes rather than plain directories, which is also the
      # layout the ArchWiki recommends: a snapshot of `/` would otherwise
      # contain every previous snapshot of `/`, nested, growing each time.
      #
      # No compression: the contents are already-compressed extents shared
      # with the live subvolume, and snapshots cost nothing until the two
      # diverge. Setting compress here would be describing a copy that does
      # not happen.
      "@snapshots" = {
        mountpoint = "/.snapshots";
        mountOptions = [ "noatime" ];
      };
      "@home-snapshots" = {
        mountpoint = "/home/.snapshots";
        mountOptions = [ "noatime" ];
      };
    };
  };
  encryptedRoot =
    if encrypt then
      {
        type = "luks";
        name = "cryptroot";
        # Read once, by the disko script, at format time. The installer writes
        # it and removes it; the installed system never sees this path -- its
        # initrd prompts for the passphrase instead. Never put it in the
        # generated flake directory: that becomes /etc/nixos and a git repo.
        passwordFile = "/tmp/nixarchy-luks.key";
        # TRIM through LUKS. Upstream accepts the trade and so do we.
        settings.allowDiscards = true;
        content = btrfs;
      }
    else
      btrfs;

  esp = {
    type = "filesystem";
    format = "vfat";
    mountpoint = "/boot";
    mountOptions = [ "umask=0077" ];
  };

  whole = {
    device = device;
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        # 2G because a NixOS /boot holds every generation's kernel and initrd.
        esp = {
          size = "2G";
          type = "EF00";
          content = esp;
        };
        root = {
          size = "100%";
          content = encryptedRoot;
        };
      };
    };
  };

  free = {
    # These are existing partition nodes, not a declaration of the GPT table.
    # The installer creates and labels them before running this disko script.
    esp = {
      device = "/dev/disk/by-partlabel/nixarchy-esp";
      type = "disk";
      content = esp;
    };
    root = {
      device = "/dev/disk/by-partlabel/nixarchy-root";
      type = "disk";
      content = encryptedRoot;
    };
  };
in
if mode == "whole" then
  { disko.devices.disk.main = whole; }
else if mode == "free" then
  {
    disko.devices.disk.nixarchyEsp = free.esp;
    disko.devices.disk.nixarchyRoot = free.root;
  }
else
  throw "nixarchy disk config: unknown installation mode: ${mode}"
