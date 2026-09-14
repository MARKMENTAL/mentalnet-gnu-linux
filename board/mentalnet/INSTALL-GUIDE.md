# Mentalnet GNU/Linux — Install & Test Guide

Mentalnet GNU/Linux is a small, TTY-only distribution for 90s Intel
Pentium-class PCs, built with Buildroot 2025.02.17. The ISO is a live
CD: the entire system runs from the CD with a read-only root, and the
same CD carries a built-in hard disk installer (`mentalnet-install`).

- Kernel: `6.12.104-mentalnet-intel32` (slimmed i386 config)
- Login: `root` / `mnlinux`
- Hostname: `mentalnet`
- Live CD size: ~100 MB

---

## 1. System requirements

### Running the live CD

| Component   | Requirement                                              |
|-------------|----------------------------------------------------------|
| CPU         | i586 (Pentium / Pentium MMX) or any newer x86; `uname -m` reports `i586` |
| RAM         | 128 MB minimum (64 MB usually works)                      |
| CD drive    | IDE/ATAPI CD-ROM (PIIX-era ATA controller)                |
| Display     | VGA text console, PS/2 keyboard/mouse                     |
| USB         | USB keyboards, mice and mass storage (UHCI/OHCI/EHCI)     |
| Serial      | 8250 UART (kernel log is mirrored to COM1)                |
| NICs (opt.) | NE2000-PCI clones (RTL8029 etc.), Intel e100/e1000/e1000e, Realtek 8139 / 8139C+ (rtl8139, incl. QEMU/Proxmox emulation), 3Com 3c59x, virtio-net (virtualized environments) |

### Installing to a hard disk

- IDE/ATA disk with at least **1 GiB** free (the whole disk is wiped)
- The machine must be able to boot from CD (El Torito, BIOS boot)

---

## 2. What's on the media

The live system mounts its root filesystem **read-only** from the CD.
Everything writable lives in RAM:

- `/tmp`, `/run`, `/dev/shm` are tmpfs
- `/var/log`, `/var/run`, `/var/cache`, `/var/spool`, `/var/tmp`
  are symlinks into those tmpfs areas

Services started at boot:

| Service    | Purpose                                        |
|------------|------------------------------------------------|
| DHCP       | `eth0` configured via udhcpc                   |
| syslogd    | kernel + system logging (to `/tmp/log`)        |
| lighttpd   | web server, port 80                            |
| dropbear   | SSH server, port 22                            |
| chronyd    | NTP time sync                                  |
| crond      | cron daemon                                    |
| nftables   | firewall rules                                 |

DNS from DHCP works on the live CD too: `/etc/resolv.conf` is a
symlink into tmpfs that `udhcpc` writes through.

### Default kernel command line

Both boot paths (live CD and installed system) ship with:

```
i8042.nomux i8042.noloop noapic acpi=off i8042.dumbkbd=1
```

| Option | Purpose |
|--------|---------|
| `i8042.nomux` / `i8042.noloop` | skip the two i8042 controller probe steps most known to confuse old or emulated keyboard controllers |
| `noapic` | use the legacy 8259 PIC instead of the IO-APIC - avoids IRQ routing/storm issues on era boards (which mostly predate the IO-APIC anyway) |
| `acpi=off` | era BIOSes (1994-1997) have broken or absent ACPI; skipping it avoids the table-parsing minefield. Power management is disabled (era-appropriate) |
| `i8042.dumbkbd=1` | do not program keyboard LEDs or expect controller ACKs - the conservative mode for flaky 8042 clones (Caps Lock light will not toggle) |

To troubleshoot a specific machine, edit the boot entry at the GRUB
menu with `e`, change the `linux` line, and boot with `Ctrl-X` or
`F10`.

---

## 3. Building from source

The build tree is a standard Buildroot 2025.02.17 checkout with the
Mentalnet configuration applied. Install the usual Buildroot host
dependencies (see `docs/manual/prerequisite.txt` in the Buildroot
manual), then:

```
make
```

Build outputs land in `output/images/`:

| File              | Purpose                                          |
|-------------------|--------------------------------------------------|
| `rootfs.iso9660`  | the bootable live CD / installer ISO             |
| `bzImage`         | the kernel (also inside the ISO and ext2 image)  |
| `rootfs.ext2`     | 2 GB raw disk image variant (for QEMU testing)   |
| `grub-eltorito.img` / `grub.img` | GRUB core images (used by the ISO) |

A full build takes a while; rebuilds after config changes are much
faster. After editing kernel fragments or the overlay, plain `make`
picks the changes up.

Every build also publishes the ISO under a unique name and prints its
SHA256 at the end of the build log. Release builds use the
`mentalnet-gnulinux-intel32-<RELEASE>-<CODENAME>.iso` convention (for
example `mentalnet-gnulinux-intel32-R1-GhostRule.iso`):

```
Published: .../output/images/mentalnet-gnulinux-intel32-20260910-212811.iso
0dcfbcb0...c308c69  output/images/mentalnet-gnulinux-intel32-20260910-212811.iso
```

Upload **that** file to hypervisors — see the Proxmox pitfall in the
troubleshooting section before attaching it to an existing VM.

---

## 4. Testing in QEMU

All commands are run from the Buildroot tree root. Exit a
`-nographic` session with `Ctrl-A x`.

### 4.1 Live CD, graphical window

```
qemu-system-i386 -m 128 -cdrom output/images/rootfs.iso9660
```

Expect the GRUB menu ("Mentalnet GNU/Linux", 10s timeout), a kernel
boot and a login prompt on the VGA console.

### 4.2 Headless (serial console)

```
qemu-system-i386 -m 128 -nographic \
  -kernel output/images/bzImage \
  -append "console=ttyS0 root=/dev/sr0 ro" \
  -cdrom output/images/rootfs.iso9660
```

This bypasses GRUB and shows the whole boot on the terminal.

### 4.3 Low-memory margin test

Same as 4.2 but with `-m 64`. The live system should still come up.

### 4.4 NE2000 network test

```
qemu-system-i386 -m 128 -nographic -nic model=ne2k_pci \
  -kernel output/images/bzImage \
  -append "console=ttyS0 root=/dev/sr0 ro" \
  -cdrom output/images/rootfs.iso9660
```

After login, `ip link` should show a configured `eth0`.

### 4.5 Disk image variant

```
qemu-system-i386 -m 128 -nographic \
  -kernel output/images/bzImage \
  -append "console=ttyS0 root=/dev/sda1 rootwait rw" \
  -drive file=output/images/rootfs.ext2,format=raw,if=ide
```

(`rootfs.ext2` also contains `/boot/bzImage` and a GRUB config for
disk boot.)

### 4.6 Full installer end-to-end test

```
# 1. create a throwaway disk
qemu-img create -f qcow2 /tmp/mn-test.qcow2 512M

# 2. boot the live CD with the test disk attached
qemu-system-i386 -m 128 -nographic \
  -kernel output/images/bzImage \
  -append "console=ttyS0 root=/dev/sr0 ro" \
  -cdrom output/images/rootfs.iso9660 \
  -drive file=/tmp/mn-test.qcow2,format=qcow2,if=ide
```

Log in and run `mentalnet-install`:

```
Disk to install to (e.g. sda): sda
Type YES to continue: YES
Proceed with installation? [y/N]: y
```

When it prints `Installation complete!`:

```
poweroff
```

Then boot **only** the test disk (no `-cdrom`, no `-kernel`) — this
exercises the installed GRUB in the MBR:

```
qemu-system-i386 -m 128 -nographic \
  -drive file=/tmp/mn-test.qcow2,format=qcow2,if=ide
```

The kernel log (mirrored to the serial console by the installed
config) should show `EXT4-fs (sda1): mounted ... r/w` and
`Run /sbin/init as init process`.

---

## 5. Installing to a hard disk (real hardware)

> **WARNING: the installer destroys ALL data on the target disk
> without further notice.** Double-check the disk name before
> confirming.

1. Boot the machine from the CD (El Torito boot).
2. Log in as `root` (password `mnlinux`).
3. Run:

   ```
   mentalnet-install
   ```

4. Answer the prompts:
   - **Disk to install to** — e.g. `sda` (the installer lists
     detected disks with their sizes first)
   - **Type YES** — destroys everything on that disk
   - the new partition table is then shown — sanity-check the disk
     size before continuing
   - **Proceed with installation? [y/N]** — final confirmation before
     anything is written to the disk

5. The installer then:
   - writes a fresh MBR partition table (root partition starts at
     sector 2048, leaving room for the GRUB core image)
   - creates an ext4 filesystem labelled `rootfs`
   - copies the whole system from the CD
   - generates `/etc/fstab`
   - installs GRUB to the MBR and writes the boot menu

6. When it prints `Installation complete!`:

   ```
   poweroff
   ```

   Remove the CD and power on — the machine now boots from its own
   disk.

The installed GRUB menu has a 5s timeout and boots automatically.

---

## 6. Post-install notes

- The installed root filesystem is **read-write**, so all services
  behave normally: chrony keeps its drift file, dropbear generates
  SSH host keys on first boot, logs persist under `/var/log`.
- DHCP DNS works the same way as on the live CD (`resolv.conf`
  symlink into tmpfs).
- Kernel boot messages are mirrored to `COM1` (ttyS0) — handy for
  debugging headless or semi-broken machines.
- Login is `root` / `mnlinux` (same as the live system).

---

## 7. Troubleshooting

| Symptom | Likely cause / fix |
|---------|--------------------|
| **How to tell which build a VM is actually running** | At the login prompt the build stamp is printed (`Mentalnet GNU/Linux build YYYYMMDD-HHMMSS`); inside the guest check `cat /etc/os-release` (`BUILD_ID=`) or `cat /proc/version`. Useful kernel build markers: `#3 ... 18:45:02` predates the rtl8139 fix, `#4 ... 20:24:17` is the first build with 8139cp. |
| **Booting the CD runs an older install instead of the live system** | Fixed: the live CD's GRUB core hardcodes `root=(cd)` (the El Torito boot CD itself), so the boot chain never touches any attached disk and an existing Mentalnet install can no longer hijack it. On builds older than this fix, the CD's GRUB searched for `/boot/bzImage` (or a marker file), and since BIOS enumerates disks before the CD, the search landed on the installed system first. |
| **Boots on Pentium Pro/i686 but hangs at kernel start on Pentium/Pentium MMX (i586)** | Fixed: the kernel is now built for `CONFIG_M586` with `CONFIG_X86_GENERIC` (no CMOV instructions). Builds before this fix used `i386_defconfig`'s `CONFIG_M686` default, which emits CMOV - instant invalid-opcode crash on real i586 CPUs. |
| **Terminal garbled / typed text repeats after a full-screen app (htop, neofetch)** | Fixed: builds before this change set `TERM=vt100` on the VGA console, so full-screen apps restored the terminal with the wrong sequences. Recovery on any running system: run `reset`. |
| **Phantom keystrokes / junk commands during or after the install** | Root cause: interrupt storms from APIC/ACPI quirks on era hardware (and emulated boards) starving the keyboard controller; the long silent copy phase also invited typed-ahead input that was replayed as shell commands. Fixed builds ship `noapic acpi=off i8042.dumbkbd=1` on both boot paths (see the kernel command line section) and show per-directory progress with an input drain before finishing. On older builds: let it finish, then run `reset`; avoid typing during the copy; `Ctrl-Q` if the console seems frozen. |
| **Proxmox: VM boots an older build despite uploading a new ISO** | Proxmox keeps every upload as a separate storage volume, and a VM's CD/DVD drive points at a specific **volume** — renaming or re-uploading a file never updates an existing drive (checksums of the new file do not help either). Delete the stale volume, upload the unique-named ISO from the build log, attach it in Hardware, and check Boot Order (an installed disk can also shadow the CD). |
| GRUB menu does not appear, or the machine reboots before booting, in QEMU | Try more RAM (`-m 256`). Memory pressure during development was the culprit more than once. |
| Kernel panic: `Unable to mount root fs` | The CD drive is on an unsupported controller. The kernel targets PIIX-era IDE/ATA; modern SATA-only setups are out of scope. |
| `Remounting root filesystem read-write ... failed` on live boot | Cosmetic. The CD root is read-only by design; all writes go to tmpfs. |
| Installer: `/dev/sdX1 did not appear after partitioning` | The kernel was still re-reading the partition table. Simply run the installer again. |
| Installer: `disk is too small` | At least 1 GiB is needed. |
| Forgot the password | It is `mnlinux` (set at build time in the Buildroot config). |
| No network | Check the NIC against the supported list in section 1. QEMU/Proxmox: `rtl8139`, `virtio-net-pci`, `ne2k_pci` or the default e1000 all work. |

---

## 8. Maintainer file map

Everything Mentalnet-specific lives here:

| File | Purpose |
|------|---------|
| `board/mentalnet/grub-embedded.cfg` | config embedded into the live CD's GRUB core: hardcodes `root=(cd)` so the CD always boots the live system, even with a Mentalnet install on an attached disk (GRUB's `(cd)` device is the El Torito boot CD itself, so nothing on any disk can influence the chain). NB: GRUB early configs support plain commands only - no comment lines, no `\` continuations, no `\|\|` operators, and `search` must be avoided because it iterates devices in BIOS order (disks first). |
| `board/mentalnet/linux-slim.config` | kernel config fragment: keeps the classic PCI NICs, ATA/ATAPI, USB HID/storage, serial and VGA console; drops wireless, sound, DRM, RAID, PCMCIA, debug |
| `board/mentalnet/overlay/usr/sbin/mentalnet-install` | the hard disk installer |
| `board/mentalnet/overlay/usr/share/mentalnet/grub-disk.cfg` | boot menu template written to installed systems (`@ROOTDEV@` is replaced) |
| `board/mentalnet/overlay/etc/resolv.conf` | symlink so DHCP DNS works on the read-only CD |
| `board/mentalnet/overlay/etc/lighttpd/` | web server configuration |
| `fs/iso9660/grub.cfg` | live CD boot menu (`root=/dev/sr0 ro`) |
| `board/mentalnet/post-build.sh` | writes the Mentalnet-branded os-release (`BUILD_ID` + `PRETTY_NAME` with the build stamp) and the login banner (wired via `BR2_ROOTFS_POST_BUILD_SCRIPT`) |
| `board/mentalnet/post-image.sh` | publishes the ISO under a unique dated name + SHA256 (wired via `BR2_ROOTFS_POST_IMAGE_SCRIPT`) |
| `localversion.config` | kernel version suffix (`-mentalnet-intel32`) |
| `.config` | Buildroot configuration: GRUB2 embedded config path and module list, kernel fragment list, e2fsprogs/grub install tools |
