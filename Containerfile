FROM quay.io/fedora/fedora-minimal:44 AS builder
COPY /usr/ /rootfs/usr/
RUN mkdir -p /rootfs/usr /rootfs/dev /rootfs/proc /rootfs/sys && \
    mount --bind /dev /rootfs/dev && \
    mount --bind /proc /rootfs/proc && \
    mount --bind /sys /rootfs/sys && \
    dnf --setopt=install_weak_deps=False install -y bootc systemd-ukify && \
    dnf --installroot=/rootfs --use-host-config \
        --setopt=install_weak_deps=False install -y \
        kernel ignition bootc systemd systemd-networkd \
        systemd-boot-unsigned podman sshd btrfs-progs \
        dosfstools selinux-policy-targeted curl sudo \
        cockpit-system cockpit-podman systemd-pam \
        bash-completion ncurses zram-generator-defaults && \
    dnf --installroot=/rootfs remove -y curl ignition && \
    dnf --installroot=/rootfs clean all && \
    rm -rf /rootfs/run/* /rootfs/var/log/* /rootfs/var/cache/* \
           /rootfs/var/lib/systemd/random-seed /rootfs/etc/machine-id \
           /rootfs/etc/dnf /rootfs/home /rootfs/root /rootfs/etc/yum.repos.d && \
    mkdir -p /rootfs/sysroot /rootfs/var/home /rootfs/var/roothome /rootfs/var/log/journal && \
    ln -s var/home /rootfs/home && \
    ln -s var/roothome /rootfs/root && \
    mkdir -p /kernel-build && \
    kver=$(ls -1 /rootfs/usr/lib/modules | head -n 1) && \
    mv /rootfs/boot/initramfs-*.img /kernel-build/initramfs.img && \
    mv /rootfs/usr/lib/modules/$kver/vmlinuz /kernel-build/vmlinuz && \
    rm -rf /rootfs/boot/*

FROM scratch AS os-base
COPY --from=builder /rootfs/ /

FROM builder AS uki-builder
RUN --mount=type=tmpfs,target=/var/tmp \
    --mount=type=bind,from=os-base,src=/,target=/target-rootfs \
    mkdir -p /out/EFI/Linux && \
    DIGEST=$(bootc container compute-composefs-digest /target-rootfs) && \
    ukify build \
      --linux=/kernel-build/vmlinuz \
      --initrd=/kernel-build/initramfs.img \
      --os-release=@/rootfs/usr/lib/os-release \
      --cmdline="composefs=$DIGEST rw enforcing=0" \
      --output=/out/EFI/Linux/bootc.efi && \
    bootc container lint --no-truncate --skip baseimage-root --rootfs /target-rootfs

FROM os-base
COPY --from=uki-builder /out/EFI /boot/EFI
LABEL containers.bootc=1
