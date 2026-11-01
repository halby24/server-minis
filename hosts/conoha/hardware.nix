# ConoHa VPS 3.0 (KVM / virtio) のハードウェア設定。
# 2026-10-31 に稼働中の Ubuntu から採取した内容を元にしている。
{ ... }:
{
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_net"
    "virtio_scsi"
    "sd_mod"
    "sr_mod"
    "ext4"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # BIOS ブート (EFI パーティションは無い)。
  # grub.devices は disko が BIOS パーティション (EF02) から自動で設定する。
  boot.loader.grub = {
    enable = true;
    efiSupport = false;
  };

  # ConoHa のコンソールは VNC。シリアルは無いので console= は付けない。
  boot.kernelParams = [ ];
}
