# arch-vm

An Arch Linux virtual machine for **learning how to install Arch by hand**, run
the same way the Windows VM on Omarchy is run: QEMU inside a Docker container
(dockurr family), KVM-accelerated, with a browser-based console.

It boots the official **Arch Linux live ISO** onto an empty 64 GB disk. Because
the blank disk has higher boot priority than the install media, you do the
install the traditional way and, once you've written a bootloader, your system
starts booting automatically on subsequent reboots. No auto-installer.

Everything mirrors the Windows VM setup:

| Windows VM                  | This repo                     |
| --------------------------- | ----------------------------- |
| `dockurr/windows` image     | `qemux/qemu` image            |
| `~/.windows:/storage`       | `./arch:/storage`             |
| `~/Windows:/shared`         | `./Arch:/shared`              |
| web UI + RDP on 8006/3389   | web viewer on 8007, SSH 2222  |

## Requirements

- Linux host with KVM and Docker (or Podman)
- ~1.6 GB free for the ISO, plus whatever the 64 GB sparse disk actually uses

## Quick start

```bash
# 1. Get the official Arch live ISO and verify it
curl -LO https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso
curl -fsS https://geo.mirror.pkgbuild.com/iso/latest/sha256sums.txt | grep 'archlinux-x86_64.iso$'
sha256sum archlinux-x86_64.iso   # compare against the checksum file

# 2. Start the VM
./omarchy-arch-vm launch         # or: docker compose up -d
```

Open **http://127.0.0.1:8007** in a browser. The Arch live environment is
waiting at a root shell.

## Layout

```
arch-vm/
├── docker-compose.yml   # the VM definition (relative paths, env-overridable)
├── archlinux-x86_64.iso # install media, bind-mounted as /boot.iso
├── arch/                # VM storage: data.img, uefi.*, qemu.mac
└── Arch/                # shared folder, mounted at /shared in the guest (9p)
```

Tuning (environment variables):

| Variable      | Default       | Meaning                    |
| ------------- | ------------- | -------------------------- |
| `RAM_SIZE`    | `4G`          | guest memory               |
| `CPU_CORES`   | `4`           | guest vCPUs                |
| `DISK_SIZE`   | `64G`         | virtual disk, growable     |
| `TZ`          | `Africa/Tunis`| guest timezone             |

Note: the ISO is bind-mounted **writable** (`./archlinux-x86_64.iso:/boot.iso`)
because QEMU opens it as a raw USB disk with write access (upstream behavior).
The file can therefore drift from the published sha after first boot; keep the
mirror checksum in your release notes for reference.

## Learn the install

The VM is UEFI with a `virtio-scsi` disk (visible in the installer at
`/dev/sda`) and NAT networking. The shortest manual path is:

```console
# on the live system:
timedatectl set-ntp true

# partition /dev/sda (parted, fdisk/cfdisk), e.g.:
#  ESP   512M  /dev/sda1  EF00
#  root  rest  /dev/sda2  ext4
mkfs.fat -F32 /dev/sda1
mkfs.ext4    /dev/sda2

mount /dev/sda2 /mnt
mount --mkdir /dev/sda1 /mnt/boot

pacstrap -K /mnt base linux linux-firmware networkmanager vim
genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt
  ln -sf /usr/share/zoneinfo/Africa/Tunis /etc/localtime
  hwclock --systohc
  sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen
  echo LANG=en_US.UTF-8 > /etc/locale.conf
  echo archbox > /etc/hostname
  systemctl enable NetworkManager
  passwd
  bootctl install            # for systemd-boot (UEFI) — creates /boot/loader/...
```

Then exit, `umount -R /mnt` and reboot (or `systemctl reboot`). The VM takes
over from the ISO automatically because the disk has higher boot priority.
After that you can browse from your host with SSH once you enable `sshd`:

```bash
ssh -p 2222 user@127.0.0.1
```

Alternative: run `archinstall` inside the VM for the guided installer.

## Managing the VM

```bash
./omarchy-arch-vm launch   # start + open the browser viewer
./omarchy-arch-vm stop
./omarchy-arch-vm restart
./omarchy-arch-vm status
```

Or directly: `docker compose stop`, `docker compose up -d`.

## Tips & troubleshooting

- Ports only listen on `127.0.0.1`. SSH forward lives on host port **2222**,
  so it won't collide with anything on 22.
- If Docker access is gated behind polkit (user not in the docker group), the
  script elevates via `pkexec` and a desktop auth prompt appears.
- If the installer ever fails, check the VM console — the boot order guarantees
  an empty disk always falls through to the ISO.
- To reset everything: `docker compose down` and delete the `arch/` contents.

## License

MIT