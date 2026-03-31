# SecureGate ISO Builder — Docker
# Kullanım:
#   docker build -t sg-builder .
#   docker run --rm -v $(pwd)/output:/output sg-builder
#
# Çıktı: output/securegate-<tarih>.iso

FROM ubuntu:22.04

LABEL maintainer="SecureGate Security Team"
LABEL description="SecureGate Zero Trust USB Kiosk ISO Builder"

ENV DEBIAN_FRONTEND=noninteractive

# Build araçlarını kur
RUN apt-get update && apt-get install -y --no-install-recommends \
    xorriso \
    grub-pc-bin \
    grub-efi-amd64-bin \
    isolinux \
    syslinux \
    syslinux-common \
    mtools \
    dosfstools \
    openssl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Proje dosyalarını kopyala
COPY iso-root/          ./iso-root/
COPY scripts/           ./scripts/
COPY certs/             ./certs/

# İzinleri ayarla
RUN chmod +x scripts/build-iso.sh \
             iso-root/system/sg-pre-check.sh \
             iso-root/system/sg-kiosk-start.sh \
             iso-root/system/sg-cleanup.sh

# ISO oluştur
RUN bash scripts/build-iso.sh /output/securegate.iso

# Çıktıyı volume'a kopyala
CMD ["sh", "-c", "cp /output/securegate.iso /output/ && echo 'ISO hazır: /output/securegate.iso'"]
