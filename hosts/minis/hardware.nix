# 暫定のハードウェア定義。
# 実際のインストール時は対象機で `nixos-generate-config --root /mnt` を実行し、
# その出力 (/mnt/etc/nixos/hardware-configuration.nix) でこのファイルを置き換えること。
# UUID は現行 Ubuntu のパーティションをそのまま使う前提。再フォーマットする場合は要修正。
{
  config,
  lib,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usbhid"
    "sd_mod"
    "rtsx_pci_sdmmc"
  ];
  boot.kernelModules = [ "kvm-intel" ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/e6f7ffaa-1864-4e2e-887b-78b372fbe290";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/8679-7BE9";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  fileSystems."/mnt/data_ssd" = {
    device = "/dev/disk/by-uuid/650b59d4-2672-42ef-84b3-dd5fc4fbb4be";
    fsType = "btrfs";
    options = [ "defaults" ];
  };

  swapDevices = [ ];

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
