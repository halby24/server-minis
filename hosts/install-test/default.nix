# 実機と同じ disko 構成で VM を組み立てる rehearsal 用ホスト。
# `nix build .#nixosConfigurations.minis-test.config.system.build.vmWithDisko`
# で、disko が作ったディスクイメージから起動する VM が得られる。
{ lib, ... }:
{
  imports = [ ./disk.nix ];

  networking.hostName = "minis-test";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # 秘密情報はテスト用の固定 age key (hosts/vm/test_age.key) で復号する
  sops.age.sshKeyPaths = lib.mkForce [ ];
  sops.age.keyFile = lib.mkForce "/var/lib/sops-nix/key.txt";
  sops.secrets.samba_halby.sopsFile = lib.mkForce ../../secrets/vm/samba.yaml;
  sops.secrets.halby_password.sopsFile = lib.mkForce ../../secrets/vm/users.yaml;
  sops.secrets.cloudflared_token.sopsFile = lib.mkForce ../../secrets/vm/cloudflared.yaml;
  sops.secrets.misskey_default_yml.sopsFile = lib.mkForce ../../secrets/vm/misskey-default.yml;
  sops.secrets.discord_bot_token.sopsFile = lib.mkForce ../../secrets/vm/discord-bot.yaml;

  system.activationScripts.vmAgeKey.text = ''
    install -D -m 0400 ${../vm/test_age.key} /var/lib/sops-nix/key.txt
  '';
  system.activationScripts.setupSecrets.deps = [ "vmAgeKey" ];
  system.activationScripts.setupSecretsForUsers.deps = [ "vmAgeKey" ];

  # データディスクが無いので VM 用のパスへ逃がす
  services.syncthing.dataDir = "/home/halby/syncthing";
  services.syncthing.configDir = "/home/halby/syncthing";

  # 外部依存・重量級のサービスは起動しない
  systemd.services.misskey.wantedBy = lib.mkForce [ ];
  systemd.services.cloudflared-misskey.wantedBy = lib.mkForce [ ];
  systemd.services.discord-bot.serviceConfig.WorkingDirectory = lib.mkForce "/tmp";

  # disko のイメージサイズ (実機のレイアウト: ESP 1G + swap 8G + root)
  disko.devices.disk.main.imageSize = "20G";
  disko.memSize = 4096;

  # VM 起動時の設定 (SSH を host:2223 に転送)
  virtualisation.vmVariantWithDisko = {
    virtualisation = {
      # ヘッドレスで起動 (コンソールはシリアル)
      graphics = false;
      forwardPorts = [
        {
          from = "host";
          host.port = 2223;
          guest.port = 22;
        }
      ];
    };
    services.getty.autologinUser = "root";
  };
}
