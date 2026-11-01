# ディスク構成 (disko)。nixos-anywhere / disko がこの定義でフォーマットする。
#
# ConoHa VPS 3.0 のブートボリュームは 30GB。旧構成と同じく BIOS ブート
# (3MB の bios_grub + ext4 root)。swap はパーティションではなく swapfile。
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/vda";
    content = {
      type = "gpt";
      partitions = {
        bios = {
          size = "3M";
          type = "EF02";
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
