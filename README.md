# AlmaLinux 9 Kickstart ISO Builder

Automated bash script to build a customized AlmaLinux 9 ISO with unattended installation via Kickstart configuration.

![bash](https://img.shields.io/badge/bash-5.0+-green?logo=gnubash&logoColor=white)
![license](https://img.shields.io/badge/license-MIT-blue)
![status](https://img.shields.io/badge/status-stable-brightgreen)

## Features

✅ **Automated Download** – Fetches latest AlmaLinux 9 ISO from official mirrors  
✅ **Customizable Installation** – Integrate your Kickstart configuration  
✅ **Dual Boot Support** – BIOS (Legacy) and UEFI boot options included  
✅ **Colored Output** – Clear, scannable progress with color-coded logging  
✅ **Error Handling** – Comprehensive validation and automatic cleanup on failure  
✅ **Dependency Checking** – Verifies all required tools before execution  
✅ **Sudo Management** – Pre-flight sudo access validation  

## Prerequisites

### System Requirements
- **OS:** Linux (tested on AlmaLinux, RHEL, Fedora, Ubuntu)
- **Storage:** ~15 GB free space (ISO + working directory)
- **User:** Sudo access (required for mount/unmount operations)

### Required Tools
```bash
wget      # For downloading the ISO
rsync     # For efficient directory copying
xorriso   # For ISO image generation
sudo      # For privileged operations
```

### Installation of Dependencies

**AlmaLinux / RHEL / Fedora:**
```bash
sudo dnf install -y wget rsync xorriso
```

**Ubuntu / Debian:**
```bash
sudo apt-get install -y wget rsync xorriso
```

## Installation

1. **Clone the repository** (or download the script):
```bash
git clone https://github.com/GenXStreamer/AlmaLinuxKickstartBuilder.git
cd AlmaLinuxKickstartBuilder
```

2. **Make the script executable:**
```bash
chmod +x build.sh
```

3. **Create your Kickstart configuration:**
There is a ks-example.cfg to get you going

## Usage

### Basic Build

```bash
./build.sh
```

The script will:
1. ✓ Check for all dependencies
2. ✓ Validate Kickstart file (`ks.cfg`)
3. ✓ Download AlmaLinux 9 ISO if not present
4. ✓ Mount the ISO and copy contents
5. ✓ Add your Kickstart configuration
6. ✓ Update GRUB bootloader with kickstart entry
7. ✓ Generate a new ISO with both BIOS and UEFI boot support
8. ✓ Output: `AlmaLinux-9-latest-kickstart.iso`

### Expected Output

```
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║        AlmaLinux 9 Kickstart ISO Builder                 ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

[ℹ] Checking sudo access...
[✓] sudo access confirmed (no password required)

[ℹ] Checking required files...
[✓] Kickstart file found: ks.cfg
[✓] ISO file found: AlmaLinux-9-latest-x86_64-dvd.iso

... (build process) ...

[✓] Kickstart ISO created successfully!

  Output:       /home/user/AlmaKickstart/tmp/../AlmaLinux-9-latest-kickstart.iso
  Size:         5.2G
  Bootable:     Yes (BIOS + UEFI)

[✓] All done!
```

## Configuration

### Script Variables

Edit these in `build.sh` to customize:

```bash
BASE_URL="https://mirrors.ukfast.co.uk/sites/almalinux.org/9/isos/x86_64/"
ISO="AlmaLinux-9-latest-x86_64-dvd.iso"
KS="ks.cfg"
WORKDIR="${HOME}/AlmaKickstart/tmp"
MOUNTDIR="${HOME}/AlmaKickstart/mount"
OUTPUT="AlmaLinux-9-latest-kickstart.iso"
```

### Kickstart File

The `ks.cfg` file controls the unattended installation. Example configurations:

**Minimal Server (no GUI):**
```kickstart
text
network --bootproto=dhcp --activate
rootpw --plaintext password123
firewall --disabled
selinux --disabled
timezone UTC
bootloader --location=mbr
zerombr
clearpart --all --initlabel
autopart --type=lvm
%packages
@core
openssh-server
%end
```

**Full Production Setup:**
```kickstart
text
network --bootproto=static --ip=192.168.1.10 --netmask=255.255.255.0 --gateway=192.168.1.1 --nameserver=8.8.8.8 --activate
rootpw --plaintext rootpass123
user --name=deploy --password=deploypass --uid=1001 --groups=wheel
firewall --service=ssh
selinux --disabled
timezone UTC --utc
bootloader --location=mbr --append="rhgb quiet"
zerombr
clearpart --all --initlabel
part /boot --fstype=xfs --size=500
part / --fstype=xfs --size=10000 --grow
%packages
@core
@development
openssh-server
curl
wget
git
vim
%end
%post
echo "Post-installation tasks..."
%end
```

For comprehensive Kickstart documentation, see [Red Hat Kickstart Documentation](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/performing_an_advanced_rhel_installation/kickstart-command-reference_installing-rhel).

## How It Works

1. **ISO Download** – Fetches the latest AlmaLinux 9 ISO from official mirrors
2. **Mount & Copy** – Mounts ISO in loop mode and copies all contents to working directory
3. **Configuration** – Embeds your `ks.cfg` Kickstart file into the ISO
4. **Boot Entry** – Adds a GRUB menu entry that automatically uses the Kickstart config
5. **ISO Generation** – Uses `xorriso` to rebuild the ISO with both BIOS and UEFI support
6. **Cleanup** – Removes temporary working directories

## Booting from Kickstart ISO

### USB Drive
```bash
# Linux/Mac
sudo dd if=AlmaLinux-9-latest-kickstart.iso of=/dev/sdX bs=4M status=progress
sudo sync

# Or use Etcher: https://www.balena.io/etcher/
```

### Virtual Machine (KVM/VMware/VirtualBox)
Simply attach the ISO as a boot device. The system will boot into the Kickstart installation menu with your custom entry available.

### Physical Server (iLO/iDRAC/IPMI)
Upload the ISO through your server's remote management interface.

## Troubleshooting

### ISO Mount Failed
```
[✗] Failed to mount ISO
```
**Solution:** Ensure `loop` module is loaded:
```bash
sudo modprobe loop
```

### xorriso Not Found
```
[✗] xorriso not found - please install it
```
**Solution:** Install xorriso package (see Prerequisites)

### Permission Denied
```
[✗] sudo access required but not available
```
**Solution:** Configure passwordless sudo or run script as root:
```bash
sudo ./build.sh
```

### Insufficient Disk Space
**Solution:** Ensure 15+ GB free space in your working directory:
```bash
df -h ${HOME}/AlmaKickstart/
```

### Broken Grub Entry
If the kickstart boot entry doesn't appear:
1. Check `WORKDIR/EFI/BOOT/grub.cfg` exists
2. Verify kickstart syntax: `ksvalidator ks.cfg`
3. Manually edit the backup: `GRUBCFG.orig`

## Project Structure

```
.
├── build.sh              # Main build script
├── ks.cfg               # Your Kickstart configuration
├── README.md            # This file
└── LICENSE              # MIT License
```

## Advanced Usage

### Custom Mirror
Change the `BASE_URL` to use a different mirror:
```bash
BASE_URL="https://mirrors.almalinux.org/almalinux/9/isos/x86_64/"
```

### Keep Working Files
Comment out the cleanup line to inspect intermediate files:
```bash
# sudo rm -rf "$WORKDIR" "$MOUNTDIR"
```

### Validate Kickstart
Before building, validate your configuration:
```bash
ksvalidator ks.cfg
```

### Re-customize Existing ISO
If you only need to modify the Kickstart file:
```bash
# Edit ks.cfg
cp ks.cfg "$WORKDIR/ks.cfg"
cd "$WORKDIR"
# Rebuild ISO with xorriso command from build.sh
```

## Performance Notes

- **Download:** 5–15 minutes (varies by bandwidth)
- **ISO Build:** 5–10 minutes (depends on disk speed)
- **Total Time:** 10–25 minutes first run

Using an SSD and a good internet connection significantly speeds up the process.

## Limitations

- **UEFI Only Systems:** Script includes BIOS + UEFI boot; works on both
- **RHEL 8/9 Compatible:** Modifications needed for other major versions
- **Sudo Required:** Some operations require elevated privileges
- **Linux Only:** Designed for Linux hosts (not macOS/Windows directly)

## Contributing

Found a bug or have a feature request? Please open an issue or submit a pull request!

## License

MIT License – see [LICENSE](LICENSE) file for details.

## Related Resources

- [AlmaLinux Official Site](https://almalinux.org)
- [Kickstart Documentation](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/performing_an_advanced_rhel_installation/kickstart-command-reference_installing-rhel)
- [xorriso Manual](https://www.gnu.org/software/xorriso/man_1_xorriso.html)
- [GRUB Configuration](https://www.gnu.org/software/grub/manual/grub/)

## Author

Created for automated AlmaLinux deployments on infrastructure requiring unattended installation.

---

**Questions?** Open an issue on GitHub or check the Troubleshooting section above.
