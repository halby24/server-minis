# rehearsal 用の disko 構成。実機 (hosts/minis/disk.nix) と同じレイアウトだが、
# データディスク (/mnt/data_ssd) は存在しないのでマウントしない。
# デバイス名は disko のテスト機構が /dev/vdX に読み替える。
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
}
