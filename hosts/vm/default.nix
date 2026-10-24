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

  # sops は VM 専用の固定 age key を使う (ダミーの秘密しか復号できない)
  sops.age.sshKeyPaths = lib.mkForce [ ];
  sops.age.keyFile = lib.mkForce "/var/lib/sops-nix/key.txt";
  sops.secrets.samba_halby.sopsFile = lib.mkForce ../../secrets/vm/samba.yaml;
  sops.secrets.halby_password.sopsFile = lib.mkForce ../../secrets/vm/users.yaml;
  system.activationScripts.setupSecretsForUsers.deps = [ "vmAgeKey" ];

  # VM は固定の age key を使う (テスト専用。ダミーの秘密しか復号できない)。
  # sops の activation (setupSecrets) より先に鍵を置く必要がある。
  system.activationScripts.vmAgeKey = {
    text = ''
      install -D -m 0400 ${./test_age.key} /var/lib/sops-nix/key.txt
    '';
  };
  system.activationScripts.setupSecrets.deps = [ "vmAgeKey" ];

  # VM にはデータディスクが無いので syncthing の置き場所を変える
  # (/home/halby 配下なら halby が自分で作成できる)
  services.syncthing.dataDir = "/home/halby/syncthing";
  services.syncthing.configDir = "/home/halby/syncthing";

  # cloudflared はダミートークン。VM では自動起動しない (Cloudflare に繋がらないため)
  sops.secrets.cloudflared_token.sopsFile = lib.mkForce ../../secrets/vm/cloudflared.yaml;
  systemd.services.cloudflared-misskey.wantedBy = lib.mkForce [ ];

  # misskey はデータディスク前提なので VM では起動しない (評価のみ)
  sops.secrets.misskey_default_yml.sopsFile = lib.mkForce ../../secrets/vm/misskey-default.yml;
  systemd.services.misskey.wantedBy = lib.mkForce [ ];

  # discord-bot はダミートークン + 作業ディレクトリだけ差し替え (起動自体は確認する)
  sops.secrets.discord_bot_token.sopsFile = lib.mkForce ../../secrets/vm/discord-bot.yaml;
  systemd.services.discord-bot.serviceConfig.WorkingDirectory = lib.mkForce "/tmp";

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
