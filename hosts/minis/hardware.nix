# ハードウェア固有の設定。ディスク構成は disk.nix (disko) が持つ。
# 2026-10-26 に実機 (Ubuntu) 上で
#   nixos-generate-config --no-filesystems --root /tmp/hwgen
# を実行して得た内容を反映している。再採取するときは同じ手順で。
{
  config,
  lib,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
