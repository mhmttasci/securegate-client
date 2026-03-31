# SecureGate USB Kiosk — Kurulum ve Build Kılavuzu

## Dizin Yapısı

```
securegate-usb/
├── iso-root/                        ← ISO'nun içeriği
│   ├── boot/
│   │   ├── grub/
│   │   │   └── grub.cfg             ← GRUB2 menüsü (BIOS + UEFI)
│   │   ├── isolinux/
│   │   │   └── isolinux.cfg         ← Legacy BIOS ISOLINUX config
│   │   ├── vmlinuz                  ← Kernel (dışarıdan eklenecek)
│   │   └── initrd.img               ← InitRAM (dışarıdan eklenecek)
│   ├── EFI/
│   │   └── BOOT/
│   │       └── grub.cfg             ← UEFI GRUB config
│   ├── app/
│   │   └── index.html               ← SecureGate Client uygulaması
│   └── system/
│       ├── securegate-kiosk.service ← systemd servisi
│       ├── sg-pre-check.sh          ← Boot öncesi sertifika/bütünlük kontrolleri
│       ├── sg-kiosk-start.sh        ← Chromium kiosk başlatıcı
│       ├── sg-cleanup.sh            ← Oturum sonu temizlik
│       └── openbox-kiosk.xml        ← Minimal pencere yöneticisi config
├── scripts/
│   └── build-iso.sh                 ← ISO build scripti
├── certs/                           ← CA ve istemci sertifikaları buraya
│   ├── ca-bundle.crt
│   ├── client.crt
│   ├── client.key
│   └── ca.crl
├── Dockerfile                       ← Reproducible build container
└── README.md
```

---

## Gereksinimler

### Build Ortamı (Ubuntu/Debian)
```bash
sudo apt-get install -y \
    xorriso grub-pc-bin grub-efi-amd64-bin \
    isolinux syslinux syslinux-common \
    mtools dosfstools openssl
```

### Temel Dağıtım

Minimal bir Linux base image gereklidir. Önerilen: **Alpine Linux** veya
**Debian netinst** üzerine kurulu custom initramfs.

Kernel ve initrd için önerilen paketler (build makinesi üzerinde):
```bash
# Debian/Ubuntu tabanlı
sudo apt-get install linux-image-amd64 initramfs-tools

# Kernel ve initrd kopyala
cp /boot/vmlinuz-$(uname -r) iso-root/boot/vmlinuz
cp /boot/initrd.img-$(uname -r) iso-root/boot/initrd.img
```

---

## Build Adımları

### 1. Sertifikaları Yerleştir

```bash
# CA sertifikasını ve istemci sertifikasını certs/ dizinine koy
cp /path/to/ca-bundle.crt certs/
cp /path/to/client.crt certs/
cp /path/to/client.key certs/   # Özel anahtar — güvenli saklayın!
cp /path/to/ca.crl certs/
```

### 2. Uygulamayı Yerleştir

```bash
# SecureGate Client HTML uygulamasını kopyala
cp securegate-client.html iso-root/app/index.html
```

### 3. ISO'yu Build Et

```bash
# Doğrudan
sudo bash scripts/build-iso.sh

# Docker ile (önerilen — reproducible build)
docker build -t sg-builder .
mkdir -p output
docker run --rm -v $(pwd)/output:/output sg-builder
```

### 4. USB'ye Yaz

```bash
# Disk adını bul
lsblk

# Yaz (sdX yerine kendi USB diskinizi yazın — dikkatli olun!)
sudo dd if=output/securegate.iso of=/dev/sdX bs=4M status=progress oflag=sync
sync
```

---

## Boot Sırası

```
Kullanıcı USB'yi takıp bilgisayarı açar
        ↓
UEFI/BIOS USB'den boot eder (F12/Boot menü)
        ↓
GRUB yüklenir (3 saniye sessiz sayaç)
        ↓
Linux kernel + initrd yüklenir
        ↓
systemd başlar
        ↓
network-online.target (DHCP/statik IP alır)
        ↓
securegate-kiosk.service başlar
        ↓
sg-pre-check.sh çalışır:
  - İstemci sertifikası kontrol
  - CRL kontrol
  - Uygulama SHA256 bütünlük
  - Ağ hazırlık
        ↓
sg-kiosk-start.sh çalışır:
  - Xorg başlar
  - Openbox (minimal WM) başlar
  - Chromium --kiosk modda açılır
        ↓
SecureGate Client ekranı → Kullanıcı görür
```

---

## Güvenlik Özellikleri

| Özellik | Yöntem |
|---------|--------|
| Read-only filesystem | squashfs / overlayfs |
| Sertifika doğrulama | openssl + CRL offline |
| Uygulama bütünlüğü | SHA256 hash kontrolü |
| Kiosk kilidi | Openbox kısayol engeli |
| Pano izolasyonu | Chromium --disable-clipboard, systemd policy |
| Temp dosyaları | Ramdisk (/tmp → tmpfs) |
| Oturum temizliği | sg-cleanup.sh (bellek + /tmp + swap) |
| AppArmor | Tüm süreçler için profil |
| Fare imleci | unclutter (sıfır gecikme) |

---

## Sık Karşılaşılan Sorunlar

**Boot etmiyor:**
- UEFI Secure Boot'u devre dışı bırakın
- USB önyükleme sırasını UEFI'de birinci yapın

**Sertifika hatası:**
- `certs/` dizinindeki sertifikaların geçerli tarihte olduğunu kontrol edin
- CRL dosyasının güncel olduğunu doğrulayın

**Siyah ekran:**
- Xorg log: `/var/log/Xorg.0.log`
- Kiosk log: `/var/log/securegate/kiosk.log`
