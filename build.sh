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
# WORKSPACE SETUP
# ============================================================================
setup_workspace() {
    log_section "Setting Up Workspace"
    
    if [ ! -d $WORKDIR ]
    then
	    sudo mkdir -p "$WORKDIR"
    fi

    if [ ! -d $MOUNTDIR ]
    then
            sudo mkdir -p "$MOUNTDIR"
    fi

    log_info "Unmounting previous mount (if any)..."
    sudo umount "$MOUNTDIR" 2>/dev/null || true
    
    #log_info "Removing previous workspace..."
    #sudo rm -rf "$WORKDIR" "$MOUNTDIR"
    
    #log_info "Creating workspace directories..."
    #sudo mkdir -p "$WORKDIR"
    #sudo mkdir -p "$MOUNTDIR"
    
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
    
    log_info "Copying ISO contents (this may take a minute)..."
    rsync -aH --delete --info=progress2 "$MOUNTDIR"/ "$WORKDIR"/ || {
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
    
    log_info "Copying kickstart file..."
    cp "$KS" "$WORKDIR/ks.cfg"
    log_success "Kickstart installed to ISO"
}

update_bootloader() {
    local grubcfg="$WORKDIR/EFI/BOOT/grub.cfg"
    
    log_section "Updating Boot Configuration"
    
    if [[ -f "$grubcfg" ]]; then
        log_info "Found grub.cfg, backing up..."
        cp "$grubcfg" "${grubcfg}.orig"
        log_success "Backup created: ${grubcfg}.orig"
        
        log_info "Adding kickstart boot entry..."
        sed -i '/menuentry .*Install AlmaLinux.*/a\
menuentry '\''Install AlmaLinux 9 Kickstart'\'' {\
    linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=AlmaLinux-9-latest-x86_64-dvd inst.ks=cdrom:/ks.cfg\
    initrdefi /images/pxeboot/initrd.img\
}\
' "$grubcfg"
        log_success "Boot entry added"
    else
        log_warn "grub.cfg not found at $grubcfg (skipping boot update)"
    fi
}

# ============================================================================
# ISO BUILDING
# ============================================================================
build_iso() {
    log_section "Building Kickstart ISO"
    
    log_info "Building ISO image (this may take a few minutes)..."
    
    cd "$WORKDIR" || return 1
    
    if xorriso -as mkisofs \
        -o "../$OUTPUT" \
        -V "AlmaLinux-9-latest-x86_64-dvd" \
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
# SUMMARY
# ============================================================================
show_summary() {
    log_section "Build Complete"
    
    local output_path="${WORKDIR}/../${OUTPUT}"
    
    if [[ -f "$output_path" ]]; then
        local size=$(du -h "$output_path" | cut -f1)
        log_success "Kickstart ISO created successfully!"
        echo
        echo -e "  ${GREEN}Output:${NC}       $output_path"
        echo -e "  ${GREEN}Size:${NC}         $size"
        echo -e "  ${GREEN}Bootable:${NC}     Yes (BIOS + UEFI)"
        echo
    else
        log_error "Output file not found!"
        return 1
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
    ║        AlmaLinux 9 Kickstart ISO Builder                  ║
    ║                                                           ║
    ╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    check_dependencies || exit 1
    check_sudo || exit 1
    check_files || exit 1
    download_iso || exit 1
    setup_workspace || exit 1
    mount_and_copy_iso || exit 1
    copy_kickstart || exit 1
    update_bootloader || exit 1
    build_iso || exit 1
    show_summary || exit 1
    
    #log_info "Cleaning up workspace..."
    #sudo rm -rf "$WORKDIR" "$MOUNTDIR"
    log_success "Cleanup complete"
    
    echo
    log_success "All done!"
    echo
}

main "$@"
