{ inputs, pkgs }:
# These are refusal tests, not install tests. They exercise the point before
# disko or sgdisk can write anything: an unsafe input must end in a clear error
# and leave the target disk alone.
pkgs.testers.runNixOSTest {
  name = "nixarchy-install-safety";

  nodes = {
    nonGpt =
      { ... }:
      {
        environment.systemPackages = [ inputs.self.packages.${pkgs.system}.install ];
        environment.etc."nixarchy/answers".text = ''
          device=/dev/vdb
          install_mode=free
          encrypt=no
          hostname=test
          username=alice
          password_hash=$6$rounds=100000$nixarchysafety$9T9YQ8x9x6mWg6x3Gm6cM8uM9sH7M3L1V7qX0vY6H4b5oJ2j3s4p5q6r7s8t9u0v1w2x3y4z5A6B7C8D9E0F1G2H3I4J5K6L7M8N9O0P1Q2R3S4T5U6V7W8X9Y0Z1
          timezone=UTC
          keymap=us
        '';
        virtualisation = {
          useEFIBoot = true;
          emptyDiskImages = [ 4096 ];
        };
      };

    fullGpt =
      { ... }:
      {
        environment.systemPackages = [ inputs.self.packages.${pkgs.system}.install ];
        environment.etc."nixarchy/answers".text = ''
          device=/dev/vdb
          install_mode=free
          encrypt=no
          hostname=test
          username=alice
          password_hash=$6$rounds=100000$nixarchysafety$9T9YQ8x9x6mWg6x3Gm6cM8uM9sH7M3L1V7qX0vY6H4b5oJ2j3s4p5q6r7s8t9u0v1w2x3y4z5A6B7C8D9E0F1G2H3I4J5K6L7M8N9O0P1Q2R3S4T5U6V7W8X9Y0Z1
          timezone=UTC
          keymap=us
        '';
        virtualisation = {
          useEFIBoot = true;
          emptyDiskImages = [ 4096 ];
        };
      };

    partitionTarget =
      { ... }:
      {
        environment.systemPackages = [ inputs.self.packages.${pkgs.system}.install ];
        environment.etc."nixarchy/answers".text = ''
          device=/dev/vdb1
          install_mode=free
          encrypt=no
          hostname=test
          username=alice
          password_hash=$6$rounds=100000$nixarchysafety$9T9YQ8x9x6mWg6x3Gm6cM8uM9sH7M3L1V7qX0vY6H4b5oJ2j3s4p5q6r7s8t9u0v1w2x3y4z5A6B7C8D9E0F1G2H3I4J5K6L7M8N9O0P1Q2R3S4T5U6V7W8X9Y0Z1
          timezone=UTC
          keymap=us
        '';
        virtualisation = {
          useEFIBoot = true;
          emptyDiskImages = [ 4096 ];
        };
      };

    bios =
      { ... }:
      {
        environment.systemPackages = [ inputs.self.packages.${pkgs.system}.install ];
        environment.etc."nixarchy/answers".text = ''
          device=/dev/vdb
          install_mode=free
          encrypt=no
          hostname=test
          username=alice
          password_hash=$6$rounds=100000$nixarchysafety$9T9YQ8x9x6mWg6x3Gm6cM8uM9sH7M3L1V7qX0vY6H4b5oJ2j3s4p5q6r7s8t9u0v1w2x3y4z5A6B7C8D9E0F1G2H3I4J5K6L7M8N9O0P1Q2R3S4T5U6V7W8X9Y0Z1
          timezone=UTC
          keymap=us
        '';
        virtualisation = {
          useEFIBoot = false;
          emptyDiskImages = [ 4096 ];
        };
      };

    bitlocker =
      { ... }:
      {
        environment.systemPackages = [ inputs.self.packages.${pkgs.system}.install ];
        environment.etc."nixarchy/answers".text = ''
          device=/dev/vdb
          install_mode=free
          encrypt=no
          hostname=test
          username=alice
          password_hash=$6$rounds=100000$nixarchysafety$9T9YQ8x9x6mWg6x3Gm6cM8uM9sH7M3L1V7qX0vY6H4b5oJ2j3s4p5q6r7s8t9u0v1w2x3y4z5A6B7C8D9E0F1G2H3I4J5K6L7M8N9O0P1Q2R3S4T5U6V7W8X9Y0Z1
          timezone=UTC
          keymap=us
        '';
        virtualisation = {
          useEFIBoot = true;
          emptyDiskImages = [ 40960 ];
        };
      };
  };

  testScript = ''
    import time

    def run_refusal(machine, expected):
        rc, output = machine.execute(
            "nixarchy-install --answers /etc/nixarchy/answers 2>&1")
        print(output)
        assert rc != 0
        assert expected in output, output

    # An MBR target cannot enter the GPT-only free-space path.
    nonGpt.wait_for_unit("multi-user.target")
    nonGpt.succeed(
        "printf 'label: dos\\nstart=2048, size=2048, type=83\\n' | "
        "sfdisk --no-reread /dev/vdb")
    run_refusal(nonGpt, "free-space install requires a GPT disk")

    # A valid GPT with no contiguous 32 GiB region must refuse before sgdisk.
    fullGpt.wait_for_unit("multi-user.target")
    fullGpt.succeed(
        "printf 'label: gpt\\nstart=2048, size=7000000, type=linux\\n' | "
        "sfdisk --no-reread /dev/vdb")
    run_refusal(fullGpt, "no contiguous free region")

    # A partition path must never be accepted as the target disk.
    partitionTarget.wait_for_unit("multi-user.target")
    partitionTarget.succeed(
        "printf 'label: gpt\\nstart=2048, size=2048, type=linux\\n' | "
        "sfdisk --no-reread /dev/vdb")
    run_refusal(partitionTarget, "not a whole disk")

    # The mode is UEFI-only and is rejected before the answers are acted on.
    bios.wait_for_unit("multi-user.target")
    run_refusal(bios, "booted in BIOS/legacy mode")

    # libblkid identifies the BitLocker volume signature before any filesystem
    # is mounted. The fake header is enough to exercise the refusal path; no
    # real Windows volume belongs in a test fixture.
    bitlocker.wait_for_unit("multi-user.target")
    bitlocker.succeed(
        "printf 'label: gpt\\nstart=2048, size=2048, type=linux\\n' | "
        "sfdisk --no-reread /dev/vdb")
    bitlocker.succeed(
        "printf '\\\\353\\\\122\\\\220-FVE-FS-' | "
        "dd of=/dev/vdb1 bs=1 seek=0 conv=notrunc status=none")
    run_refusal(bitlocker, "BitLocker was detected")
  '';
}
