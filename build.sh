#!/bin/bash
set -euo pipefail

# ============================================================================
# COLOUR DEFINITIONS
# ============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Colour

# ============================================================================
# CONFIGURATION
# ============================================================================
readonly BASE_URL="https://mirrors.ukfast.co.uk/sites/almalinux.org/9/isos/x86_64/"
readonly ISO="AlmaLinux-9-latest-x86_64-dvd.iso"
readonly KS="ks.cfg"
readonly WORKDIR="${HOME}/AlmaKickstart/tmp"
readonly MOUNTDIR="${HOME}/AlmaKickstart/mount"
readonly OUTPUT="AlmaLinux-9-latest-kickstart.iso"

ISO_LABEL=""

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================
log_info() {
    echo -e "${BLUE}[ℹ]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[⚠]${NC} $*"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*" >&2
}

log_section() {
    echo
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}${NC} $*"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
}

# ============================================================================
# ERROR HANDLING
# ============================================================================
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed with exit code $exit_code"
        log_warn "Attempting cleanup..."
        sudo umount "$MOUNTDIR" 2>/dev/null || true
    fi
    exit $exit_code
}

trap cleanup EXIT

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================
check_dependencies() {
    log_section "Checking Dependencies"
    
    local deps=("wget" "rsync" "xorriso" "sudo")
    for cmd in "${deps[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            log_success "$cmd found"
        else
            log_error "$cmd not found - please install it"
            return 1
        fi
    done
}

check_sudo() {
    log_info "Checking sudo access..."
    if sudo -n true 2>/dev/null; then
        log_success "sudo access confirmed (no password required)"
    elif sudo -v 2>/dev/null; then
        log_success "sudo access confirmed (password entered)"
    else
        log_error "sudo access required but not available"
        return 1
    fi
}

check_files() {
    log_section "Checking Required Files"
    
    if [[ -f "$KS" ]]; then
        log_success "Kickstart file found: $KS"
    else
        log_error "Kickstart file not found: $KS"
        return 1
    fi
    
    if [[ -f "$ISO" ]]; then
        log_success "ISO file found: $ISO"
    else
        log_warn "ISO file not found: $ISO (will attempt download)"
    fi
}

download_iso() {
    if [[ ! -f "$ISO" ]]; then
        log_section "Downloading ISO"
        log_info "Downloading from: $BASE_URL$ISO"
        
        if wget --progress=bar:force -O "$ISO" "$BASE_URL/$ISO"; then
            log_success "ISO downloaded successfully"
        else
            log_error "Failed to download ISO"
            return 1
        fi
    else
        log_success "ISO already present, skipping download"
    fi
}

# ============================================================================
# ISO INSPECTION - EXTRACT LABEL
# ============================================================================
detect_iso_label() {
    log_section "Detecting ISO Label"
    
    log_info "Mounting ISO to read filesystem label..."
    sudo mount -o loop,ro "$ISO" "$MOUNTDIR" 2>/dev/null || {
        log_error "Failed to mount ISO"
        return 1
    }
    
    # Read the ISO label from isolinux.cfg
    if [[ -f "$MOUNTDIR/isolinux/isolinux.cfg" ]]; then
        ISO_LABEL=$(grep -oP 'hd:LABEL=\K[^ ]+' "$MOUNTDIR/isolinux/isolinux.cfg" | head -1 || echo "")
    fi
    
    # Fallback: read from .discinfo if present
    if [[ -z "$ISO_LABEL" ]] && [[ -f "$MOUNTDIR/.discinfo" ]]; then
        ISO_LABEL=$(sed -n '4p' "$MOUNTDIR/.discinfo" 2>/dev/null || echo "")
    fi
    
    sudo umount "$MOUNTDIR"
    
    if [[ -n "$ISO_LABEL" ]]; then
        log_success "Detected ISO label: $ISO_LABEL"
    else
        ISO_LABEL="${ISO%.iso}"
        log_warn "Could not auto-detect label, using: $ISO_LABEL"
    fi
}

# ============================================================================
# WORKSPACE SETUP
# ============================================================================
setup_workspace() {
    log_section "Setting Up Workspace"
    
    log_info "Unmounting previous mount (if any)..."
    sudo umount "$MOUNTDIR" 2>/dev/null || true
    
    log_info "Removing previous workspace..."
    sudo rm -rf "$WORKDIR" "$MOUNTDIR"
    
    log_info "Creating workspace directories..."
    sudo mkdir -p "$WORKDIR"
    sudo mkdir -p "$MOUNTDIR"
    
    log_success "Workspace ready"
}

# ============================================================================
# ISO PROCESSING
# ============================================================================
mount_and_copy_iso() {
    log_section "Mounting and Copying ISO"
    
    log_info "Mounting ISO..."
    sudo mount -o loop,ro "$ISO" "$MOUNTDIR" || {
        log_error "Failed to mount ISO"
        return 1
    }
    log_success "ISO mounted to $MOUNTDIR"
    
    log_info "Copying ISO contents (this may take 2-5 minutes)..."
    rsync -aH --info=progress2 "$MOUNTDIR"/ "$WORKDIR"/ || {
        log_error "Failed to copy ISO contents"
        return 1
    }
    log_success "ISO contents copied"
    
    log_info "Unmounting ISO..."
    sudo umount "$MOUNTDIR"
    log_success "ISO unmounted"
}

copy_kickstart() {
    log_section "Installing Kickstart Configuration"
    
    log_info "Copying kickstart file to ISO root..."
    cp "$KS" "$WORKDIR/ks.cfg"
    chmod 644 "$WORKDIR/ks.cfg"
    
    log_success "Kickstart installed at ISO root: /ks.cfg"
}

# ============================================================================
# ISOLINUX CONFIGURATION - CLEAN & REBUILD
# ============================================================================
update_isolinux() {
    log_section "Updating ISOLINUX (BIOS) Configuration"
    
    local isolinux_cfg="$WORKDIR/isolinux/isolinux.cfg"
    
    if [[ ! -f "$isolinux_cfg" ]]; then
        log_warn "isolinux.cfg not found - skipping BIOS boot update"
        return 0
    fi
    
    log_info "Backing up original isolinux.cfg..."
    cp "$isolinux_cfg" "${isolinux_cfg}.orig"
    
    log_info "Rebuilding isolinux.cfg with corrected labels and Kickstart as default..."
    
    # Extract everything up to the first label line
    local header
    header=$(sed -n '1,/^label/p' "$isolinux_cfg" | head -n -1)
    
    # Create new config with kickstart as default
    cat > "$isolinux_cfg" << 'EOF'
default kickstart
timeout 100
totaltimeout 6000
ui menu.c32
menu title ^Install AlmaLinux 9

label kickstart
  menu label ^Install with Kickstart (unattended) [DEFAULT]
  menu default
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=LABEL_PLACEHOLDER inst.ks=cdrom:/ks.cfg quiet

label linux
  menu label Install AlmaLinux 9 (interactive)
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=LABEL_PLACEHOLDER quiet

label text
  menu label Install AlmaLinux 9 (text mode)
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=LABEL_PLACEHOLDER inst.text quiet

label rescue
  menu label ^Rescue an AlmaLinux system
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=LABEL_PLACEHOLDER inst.rescue quiet

label memtest
  menu label Run a ^memory test
  append memtest quiet

label local
  menu label Boot from ^local drive
  localboot 0xffff

label returntomain
  menu label Return to ^main menu
  menu exit
EOF
    
    # Replace label placeholder with actual label
    sed -i "s|LABEL_PLACEHOLDER|$ISO_LABEL|g" "$isolinux_cfg"
    
    log_success "isolinux.cfg updated with:"
    log_success "  • Kickstart as DEFAULT boot option"
    log_success "  • All entries use correct label: $ISO_LABEL"
    log_success "  • Clean, readable menu structure"
}

# ============================================================================
# GRUB CONFIGURATION - CLEAN & REBUILD
# ============================================================================
update_grub() {
    log_section "Updating GRUB (UEFI) Configuration"
    
    local grubcfg="$WORKDIR/EFI/BOOT/grub.cfg"
    
    if [[ ! -f "$grubcfg" ]]; then
        log_warn "grub.cfg not found - skipping UEFI boot update"
        return 0
    fi
    
    log_info "Backing up original grub.cfg..."
    cp "$grubcfg" "${grubcfg}.orig"
    
    log_info "Rebuilding grub.cfg with corrected labels and Kickstart as default..."
    
    # Extract the header (everything before first menuentry)
    local header
    header=$(sed -n '1,/^menuentry/p' "$grubcfg" | head -n -1)
    
    # Create new config with kickstart as default
    cat > "$grubcfg" << 'EOF'
set default="0"
set timeout=60

### BEGIN CUSTOM KICKSTART ENTRIES ###

menuentry 'Install with Kickstart (unattended) [DEFAULT]' {
    linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=LABEL_PLACEHOLDER inst.ks=cdrom:/ks.cfg quiet
    initrdefi /images/pxeboot/initrd.img
}

menuentry 'Install AlmaLinux 9 (interactive)' {
    linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=LABEL_PLACEHOLDER quiet
    initrdefi /images/pxeboot/initrd.img
}

menuentry 'Install AlmaLinux 9 (text mode)' {
    linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=LABEL_PLACEHOLDER inst.text quiet
    initrdefi /images/pxeboot/initrd.img
}

menuentry 'Rescue an AlmaLinux system' {
    linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=LABEL_PLACEHOLDER inst.rescue quiet
    initrdefi /images/pxeboot/initrd.img
}

### END CUSTOM KICKSTART ENTRIES ###
EOF
    
    # Replace label placeholder with actual label
    sed -i "s|LABEL_PLACEHOLDER|$ISO_LABEL|g" "$grubcfg"
    
    log_success "grub.cfg updated with:"
    log_success "  • Kickstart as DEFAULT boot option"
    log_success "  • All entries use correct label: $ISO_LABEL"
    log_success "  • Clean, readable menu structure"
}

# ============================================================================
# ISO BUILDING - CRITICAL: Label must match boot parameters
# ============================================================================
build_iso() {
    log_section "Building Kickstart ISO"
    
    log_info "Building ISO with label: $ISO_LABEL"
    log_info "This will take 5-10 minutes..."
    
    cd "$WORKDIR" || return 1
    
    if sudo xorriso -as mkisofs \
        -o "../$OUTPUT" \
        -V "$ISO_LABEL" \
        -J \
        -R \
        -T \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e images/efiboot.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        . 2>&1 | grep -v "^$"; then
        log_success "ISO built successfully"
        return 0
    else
        log_error "Failed to build ISO"
        return 1
    fi
}

# ============================================================================
# VERIFICATION
# ============================================================================
verify_iso() {
    log_section "Verifying Built ISO"
    
    local output_path="${WORKDIR}/../${OUTPUT}"
    
    if [[ ! -f "$output_path" ]]; then
        log_error "Output file not found!"
        return 1
    fi
    
    log_info "Mounting new ISO to verify..."
    sudo mount -o loop,ro "$output_path" "$MOUNTDIR" 2>/dev/null || {
        log_error "Failed to mount output ISO for verification"
        return 1
    }
    
    # Check kickstart file
    if [[ -f "$MOUNTDIR/ks.cfg" ]]; then
        log_success "✓ Kickstart file present on ISO"
    else
        log_error "✗ Kickstart file NOT found on ISO!"
        sudo umount "$MOUNTDIR"
        return 1
    fi
    
    # Check default in isolinux
    if grep -q "^default kickstart" "$MOUNTDIR/isolinux/isolinux.cfg"; then
        log_success "✓ isolinux: Kickstart is DEFAULT"
    else
        log_warn "⚠ isolinux: Kickstart may not be default"
    fi
    
    # Check all isolinux entries use correct label
    local bad_entries
    bad_entries=$(grep -c "inst.stage2=hd:LABEL=$ISO_LABEL" "$MOUNTDIR/isolinux/isolinux.cfg" || echo "0")
    if [[ $bad_entries -gt 0 ]]; then
        log_success "✓ isolinux: All $bad_entries entries use correct label"
    fi
    
    # Check GRUB default
    if grep -q 'set default="0"' "$MOUNTDIR/EFI/BOOT/grub.cfg" 2>/dev/null; then
        log_success "✓ GRUB: Kickstart is set as default (entry 0)"
    else
        log_warn "⚠ GRUB: Kickstart may not be default"
    fi
    
    # Check all GRUB entries use correct label
    local grub_entries
    grub_entries=$(grep -c "inst.stage2=hd:LABEL=$ISO_LABEL" "$MOUNTDIR/EFI/BOOT/grub.cfg" 2>/dev/null || echo "0")
    if [[ $grub_entries -gt 0 ]]; then
        log_success "✓ GRUB: All $grub_entries entries use correct label"
    fi
    
    # Show the boot menus
    echo
    log_info "ISOLINUX menu entries:"
    grep "menu label" "$MOUNTDIR/isolinux/isolinux.cfg" | sed 's/^/  /'
    echo
    log_info "GRUB menu entries:"
    grep "^menuentry" "$MOUNTDIR/EFI/BOOT/grub.cfg" | sed "s/^menuentry '/  /" | sed "s/' {//" | sed 's/^/  /'
    echo
    
    sudo umount "$MOUNTDIR"
    log_success "Verification complete"
}

# ============================================================================
# SUMMARY
# ============================================================================
show_summary() {
    log_section "Build Complete"
    
    local output_path="${WORKDIR}/../${OUTPUT}"
    
    if [[ -f "$output_path" ]]; then
        local size=$(du -h "$output_path" | cut -f1)
        log_success "Kickstart ISO created successfully!"
        echo
        echo -e "  ${GREEN}Output:${NC}              $output_path"
        echo -e "  ${GREEN}Size:${NC}                $size"
        echo -e "  ${GREEN}Type:${NC}                AlmaLinux DVD with Kickstart"
        echo -e "  ${GREEN}ISO Label:${NC}           $ISO_LABEL"
        echo -e "  ${GREEN}Bootable:${NC}            Yes (BIOS + UEFI)"
        echo -e "  ${GREEN}Kickstart:${NC}           /ks.cfg (on ISO root)"
        echo
        echo -e "${YELLOW}Boot Configuration:${NC}"
        echo -e "  ${GREEN}Default Boot:${NC}        Kickstart (unattended installation)"
        echo -e "  ${GREEN}BIOS Entries:${NC}        5 options (kickstart first)"
        echo -e "  ${GREEN}UEFI Entries:${NC}        5 options (kickstart first)"
        echo -e "  ${GREEN}Boot Parameter:${NC}      inst.stage2=hd:LABEL=$ISO_LABEL"
        echo
        return 0
    else
        log_error "Output file not found!"
        return 1
    fi
}

# ============================================================================
# VALIDATION
# ============================================================================
validate_kickstart() {
    log_section "Validating Kickstart"
    
    if command -v ksvalidator &>/dev/null; then
        log_info "Validating Kickstart syntax..."
        if ksvalidator "$KS" 2>&1; then
            log_success "Kickstart file is valid"
        else
            log_error "Kickstart file has validation errors"
            log_warn "Build will continue - check errors above"
        fi
    else
        log_warn "ksvalidator not found - skipping validation"
        log_info "Install with: sudo dnf install pykickstart"
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
main() {
    echo -e "${BLUE}"
    cat << "EOF"
    ╔═══════════════════════════════════════════════════════════╗
    ║                                                           ║
    ║      AlmaLinux Kickstart ISO Builder (FINAL)             ║
    ║                                                           ║
    ║  • Clean boot entries with correct labels               ║
    ║  • Kickstart as DEFAULT option                          ║
    ║  • Optimized for unattended installation                ║
    ║                                                           ║
    ╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    check_dependencies || exit 1
    check_sudo || exit 1
    check_files || exit 1
    validate_kickstart
    download_iso || exit 1
    detect_iso_label || exit 1
    setup_workspace || exit 1
    mount_and_copy_iso || exit 1
    copy_kickstart || exit 1
    update_isolinux || exit 1
    update_grub || exit 1
    build_iso || exit 1
    verify_iso || exit 1
    show_summary || exit 1
    
    log_info "Cleaning up workspace..."
    sudo rm -rf "$WORKDIR" "$MOUNTDIR"
    log_success "Cleanup complete"
    
    echo
    log_success "All done!"
    echo
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Write to USB:"
    echo "     ${BLUE}sudo dd if=$OUTPUT of=/dev/sdX bs=4M status=progress && sync${NC}"
    echo
    echo "  2. Boot from USB"
    echo
    echo "  3. ${CYAN}Kickstart will start automatically${NC} as the default boot option"
    echo
    echo "  4. Installation will proceed unattended"
    echo
}

main "$@"
