#!/bin/bash
# build-iso.sh
# SecureGate USB Kiosk ISO Oluşturucu
# Gereksinimler: xorriso, grub-pc-bin, grub-efi-amd64-bin, isolinux, syslinux-utils
#
# Kullanım:
#   sudo bash build-iso.sh [--output securegate.iso] [--label "SECUREGATE"]
#
# Çıktı:::
#   securegate-<tarih>.iso  — BIOS + UEFI önyüklenebilir ISO

set -euo pipefail

###############################################################################
# Değişkenler
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
ISO_ROOT="$SCRIPT_DIR/iso-root"
OUTPUT_ISO="${1:-$SCRIPT_DIR/securegate-$(date +%Y%m%d-%H%M).iso}"
VOLUME_LABEL="SECUREGATE"
GRUB_MODULES="part_gpt part_msdos fat ext2 iso9660 linux normal boot \
              search search_fs_file search_fs_uuid chain configfile \
              echo test true"

###############################################################################
# Log fonksiyonu
###############################################################################
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()  { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_err()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

###############################################################################
# Araç kontrolü
###############################################################################
check_tools() {
    log_info "Gerekli araçlar kontrol ediliyor..."
    local missing=()
    for tool in xorriso grub-mkstandalone mcopy mformat; do
        command -v "$tool" &>/dev/null || missing+=("$tool")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        log_err "Eksik araçlar: ${missing[*]}\nKurulum: sudo apt-get install xorriso grub-pc-bin grub-efi-amd64-bin isolinux syslinux mtools"
    fi
    log_ok "Tüm araçlar mevcut"
}

###############################################################################
# Dizin yapısını hazırla
###############################################################################
prepare_dirs() {
    log_info "Derleme dizinleri hazırlanıyor..."
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"/{grub,efi}
    log_ok "Dizinler hazır: $BUILD_DIR"
}

###############################################################################
# Uygulama dosyalarını kopyala
###############################################################################
copy_app_files() {
    log_info "Uygulama dosyaları kopyalanıyor..."

    # index.html — SecureGate client arayüzü
    if [ ! -f "$ISO_ROOT/app/index.html" ]; then
        log_err "Uygulama dosyası bulunamadı: $ISO_ROOT/app/index.html"
    fi

    # SHA256 hash hesapla (bütünlük kontrolü için)
    log_info "Uygulama SHA256 hash hesaplanıyor..."
    (cd "$ISO_ROOT/app" && find . -type f -exec sha256sum {} \;) > "$ISO_ROOT/system/app.sha256"
    log_ok "Hash dosyası oluşturuldu: app.sha256"
}

###############################################################################
# GRUB BIOS görüntüsü oluştur
###############################################################################
build_bios_grub() {
    log_info "GRUB BIOS boot görüntüsü oluşturuluyor..."
    grub-mkstandalone \
        --format=i386-pc \
        --output="$BUILD_DIR/grub/core.img" \
        --install-modules="$GRUB_MODULES" \
        --modules="biosdisk" \
        "boot/grub/grub.cfg=$ISO_ROOT/boot/grub/grub.cfg"

    # BIOS boot.img ile birleştir
    cat /usr/lib/grub/i386-pc/cdboot.img "$BUILD_DIR/grub/core.img" \
        > "$BUILD_DIR/grub/bios.img"

    log_ok "BIOS GRUB görüntüsü hazır"
}

###############################################################################
# GRUB EFI görüntüsü oluştur
###############################################################################
build_efi_grub() {
    log_info "GRUB EFI görüntüsü oluşturuluyor..."
    grub-mkstandalone \
        --format=x86_64-efi \
        --output="$BUILD_DIR/efi/bootx64.efi" \
        --install-modules="$GRUB_MODULES" \
        "boot/grub/grub.cfg=$ISO_ROOT/EFI/BOOT/grub.cfg"

    # FAT12 EFI disk görüntüsü oluştur
    dd if=/dev/zero of="$BUILD_DIR/efi/efiboot.img" bs=1M count=4 status=none
    mformat -i "$BUILD_DIR/efi/efiboot.img" -F ::
    mmd -i "$BUILD_DIR/efi/efiboot.img" ::/EFI
    mmd -i "$BUILD_DIR/efi/efiboot.img" ::/EFI/BOOT
    mcopy -i "$BUILD_DIR/efi/efiboot.img" \
          "$BUILD_DIR/efi/bootx64.efi" \
          ::/EFI/BOOT/bootx64.efi

    log_ok "EFI GRUB görüntüsü hazır"
}

###############################################################################
# ISO oluştur
###############################################################################
build_iso() {
    log_info "ISO dosyası oluşturuluyor: $OUTPUT_ISO"

    xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid "$VOLUME_LABEL" \
        -appid "SecureGate Zero Trust Kiosk" \
        -publisher "SecureGate Security Team" \
        -preparer "SecureGate Build System" \
        \
        -eltorito-boot boot/isolinux/isolinux.bin \
        -eltorito-catalog boot/isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --eltorito-alt-boot \
        \
        -eltorito-alt-boot \
        -e boot/efiboot.img \
        -no-emul-boot \
        \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        -isohybrid-gpt-basdat \
        \
        -output "$OUTPUT_ISO" \
        \
        -graft-points \
            "$ISO_ROOT" \
            "boot/efiboot.img=$BUILD_DIR/efi/efiboot.img" \
            "boot/isolinux/isolinux.bin=/usr/lib/ISOLINUX/isolinux.bin" \
            "boot/isolinux/ldlinux.c32=/usr/lib/syslinux/modules/bios/ldlinux.c32"

    log_ok "ISO oluşturuldu: $OUTPUT_ISO"
}

###############################################################################
# USB'ye yaz (opsiyonel)
###############################################################################
write_usb() {
    if [ -z "${USB_DEVICE:-}" ]; then return; fi
    log_warn "USB'ye yazılıyor: $USB_DEVICE — TÜM VERİLER SİLİNECEK!"
    read -p "Onaylıyor musunuz? (yes/NO) " confirm
    [ "$confirm" = "yes" ] || { log_info "İptal edildi."; return; }

    dd if="$OUTPUT_ISO" of="$USB_DEVICE" bs=4M status=progress oflag=sync
    sync
    log_ok "USB yazma tamamlandı: $USB_DEVICE"
}

###############################################################################
# ISO doğrula
###############################################################################
verify_iso() {
    log_info "ISO doğrulanıyor..."
    local size=$(du -sh "$OUTPUT_ISO" | cut -f1)
    log_ok "ISO boyutu: $size"

    # SHA256 üret
    sha256sum "$OUTPUT_ISO" > "${OUTPUT_ISO%.iso}.sha256"
    log_ok "Checksum: ${OUTPUT_ISO%.iso}.sha256"

    # ISO içeriğini listele
    log_info "ISO içeriği (kök dizin):"
    xorriso -indev "$OUTPUT_ISO" -ls / 2>/dev/null | head -20 || true
}

###############################################################################
# Ana akış
###############################################################################
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   SecureGate ISO Build Script v1.0       ║"
echo "║   Zero Trust USB Kiosk                   ║"
echo "╚══════════════════════════════════════════╝"
echo ""

check_tools
prepare_dirs
copy_app_files
build_bios_grub
build_efi_grub
build_iso
verify_iso
write_usb

echo ""
log_ok "Build tamamlandı!"
log_ok "ISO: $OUTPUT_ISO"
echo ""
echo "USB'ye yazmak için:"
echo "  sudo dd if=$OUTPUT_ISO of=/dev/sdX bs=4M status=progress oflag=sync"
echo "  veya: sudo USB_DEVICE=/dev/sdX bash build-iso.sh"
echo ""
