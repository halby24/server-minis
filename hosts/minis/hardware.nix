# ハードウェア固有の設定。ディスク構成は disk.nix (disko) が持つ。
# 実機では `nixos-generate-config --no-filesystems --root /mnt` の出力を参考に、
# カーネルモジュール等をこのファイルへ取り込むこと。
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

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
