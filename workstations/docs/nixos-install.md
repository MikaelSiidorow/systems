# Installing NixOS on the ThinkPad X1 Carbon Gen 9

This procedure replaces Pop!\_OS while preserving the existing disk structure:

- EFI system partition: `nvme0n1p1`
- LUKS2 container: `nvme0n1p3`, opened as `cryptdata`
- LVM root logical volume: `data-root`
- Randomly encrypted swap partition: `nvme0n1p4`

The Pop!\_OS recovery partition is left untouched, although it will no longer restore
the files removed from the root logical volume.

## Before booting the installer

1. Back up everything in the home directory to another encrypted device and verify
   that the backup can be read.
2. Back up `~/.config/sops/age/keys.txt` separately. It is required to decrypt the
   repository secrets after installation.
3. Commit and push the `wip/nixos-plasma` branch, or copy the repository to separate media.
   Formatting the root logical volume removes the local checkout.
4. Create and boot an official NixOS installer USB in UEFI mode.

Secure Boot is currently disabled. Leave it disabled for the initial installation;
authenticated boot can be configured and tested separately afterward.

## Verify the target disk

These commands must show the same identifiers before any destructive operation:

```bash
lsblk -e7 -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,UUID,PARTUUID,MOUNTPOINTS,MODEL

readlink -f /dev/disk/by-uuid/d2c56f4e-063c-494d-b1cd-990c5cb32664
readlink -f /dev/disk/by-partuuid/181cbe5b-0809-41cf-8bab-d262e7748942
readlink -f /dev/disk/by-partuuid/f625397a-0e9b-4311-b5c3-a02a07f3bece
```

Expected results are `nvme0n1p3`, `nvme0n1p1`, and `nvme0n1p4`, respectively.
Stop if they differ.

## Prepare and mount the existing encrypted layout

Opening LUKS and activating LVM are non-destructive. `mkfs.ext4` permanently erases
the existing Pop!\_OS root filesystem, including the home directory.

```bash
sudo cryptsetup open \
  /dev/disk/by-uuid/d2c56f4e-063c-494d-b1cd-990c5cb32664 \
  cryptdata
sudo vgchange -ay

# DESTRUCTIVE: run only after verifying the backup and target device.
sudo mkfs.ext4 -L nixos /dev/mapper/data-root

sudo mount /dev/mapper/data-root /mnt
sudo mkdir -p /mnt/boot /mnt/home/mikaelsiidorow
sudo mount \
  /dev/disk/by-partuuid/181cbe5b-0809-41cf-8bab-d262e7748942 \
  /mnt/boot
```

Do not format the EFI, LUKS, or swap partitions.

## Install from the flake

Clone the pushed installation branch into the future home directory:

```bash
sudo git clone --branch wip/nixos-plasma \
  https://github.com/MikaelSiidorow/systems.git \
  /mnt/home/mikaelsiidorow/systems
sudo chown -R 1000:100 /mnt/home/mikaelsiidorow

sudo nixos-install \
  --flake /mnt/home/mikaelsiidorow/systems/workstations#nixos-laptop
```

Set the normal user's password after installation:

```bash
sudo nixos-enter --root /mnt -c 'passwd mikaelsiidorow'
```

Restore the SOPS age key before the first boot:

```bash
sudo install -d -m 700 -o 1000 -g 100 \
  /mnt/home/mikaelsiidorow/.config/sops/age
sudo install -m 600 -o 1000 -g 100 \
  /path/to/backup/keys.txt \
  /mnt/home/mikaelsiidorow/.config/sops/age/keys.txt
```

Replace `/path/to/backup/keys.txt` with the mounted backup location. Then unmount and
reboot:

```bash
cd /
sudo umount -R /mnt
sudo vgchange -an
sudo cryptsetup close cryptdata
sudo reboot
```

Remove the installer USB when the firmware restarts.

## Encryption notes

The existing LUKS2 container is retained, so reinstalling NixOS does not weaken or
replace its cipher or passphrase KDF. The root filesystem is encrypted at rest, and
swap receives a fresh random encryption key at every boot. Randomly encrypted swap
does not support hibernation.

The EFI system partition must remain unencrypted so firmware can read it. With
Secure Boot disabled, disk encryption protects confidentiality against ordinary
theft but does not prevent an attacker with repeated physical access from modifying
the boot files. Configure Secure Boot only after the basic NixOS installation is
known to boot reliably.
