# VM での動作確認用ホスト。
#   nix build .#nixosConfigurations.minis-vm.config.system.build.vm
#   ./result/bin/run-minis-vm-vm
# 実機と同じ modules/common.nix を読み、仮想ハードウェア設定だけ足す。
{ lib, ... }:
{
  networking.hostName = "minis-vm";

  # ベース設定としても評価が通るように root を宣言しておく (qemu-vm が上書きする)
  fileSystems."/" = {
    device = "/dev/vda";
    fsType = "ext4";
  };
  boot.loader.grub.enable = false;

  virtualisation.vmVariant = {
    virtualisation = {
      memorySize = 4096;
      cores = 2;
      diskSize = 8192;
      graphics = false;
      forwardPorts = [
        {
          from = "host";
          host.port = 2222;
          guest.port = 22;
        }
      ];
    };

    # コンソールは自動ログイン (VM なので)
    services.getty.autologinUser = lib.mkForce "halby";
  };
}
