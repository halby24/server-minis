# ディスク構成 (disko)。nixos-anywhere / disko がこの定義でフォーマットする。
#
# システムディスク (NVMe) は毎回まっさらにする前提。データディスク (SATA SSD) は
# フォーマットせず、既存の btrfs をラベルでマウントするだけ。
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          type = "EF00";
          size = "1G";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [
              "fmask=0077"
              "dmask=0077"
            ];
          };
        };
        swap = {
          size = "8G";
          content = {
            type = "swap";
            resumeDevice = false;
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };

  # データディスク: 既存の btrfs をそのまま使う（disko では触らない）
  fileSystems."/mnt/data_ssd" = {
    device = "/dev/disk/by-label/data_ssd";
    fsType = "btrfs";
    options = [ "defaults" ];
  };
}
