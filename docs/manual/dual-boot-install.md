---
title: Dual boot install
---

# Dual boot install

nixarchy has a fresh-machine installer with **Full disk install** and **Free
space install** modes. The latter is UEFI-only, requires at least 32 GiB of
contiguous unallocated space on a GPT disk, and creates a separate nixarchy ESP
and root partition without adopting or formatting an existing partition.

Omarchy ships an ISO whose installer offers a **Free space install** next to
Windows, encrypts the partition with LUKS, and then runs `limine-scan` to add
the other operating systems to its bootloader.

When a Windows EFI loader is found on an existing ESP, Limine gets a
**Windows Boot Manager** entry that references that ESP by PARTUUID. The Windows
ESP is mounted read-only during detection and is never modified. The free-space
design is tracked in [issue #47](https://github.com/olafkfreund/nixarchy/issues/47).

## Free-space install

1. **Make room on the Windows side** exactly as upstream describes — Disk
   Management, *Shrink Volume*, and turn BitLocker off first, since it encrypts
   the whole drive rather than a partition. That half of
   [the upstream page](https://omarchy.org/manual/dual-boot-install/) is about
   Windows, not Omarchy, and applies unchanged.

2. Boot the nixarchy ISO in UEFI mode and choose **Free space install** when the
   disk has a suitable contiguous free region. The installer creates and
   formats only `nixarchy-esp` and `nixarchy-root` in that region.

3. Confirm the summary. If the disk changed, the free-space layout no longer
   matches the recorded partition table and the installer refuses to proceed.

If there is no suitable region, or if BitLocker or another unsupported disk
state is detected, the installer refuses rather than guessing. Users who need
dual boot on a layout the installer cannot handle must still install NixOS
alongside the existing OS first and then add nixarchy to that NixOS
configuration as described on [the getting-started page](getting-started).
