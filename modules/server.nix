# サーバーとしての基本設定。
# 現行 minis の待ち受けポートを明示的に許可し、tailscale と podman を有効にする。
{ lib, pkgs, ... }:
{
  # 現行 Ubuntu では ufw が無効だったため、ここで初めて明示的な制限をかける。
  # ポートは 2026-10-24 時点の稼働サービスに合わせている (docs/current-state.md 参照)。
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      21 # vsftpd (移行後に廃止予定)
      22 # ssh
      139 # samba
      445 # samba
      2226 # gitea ssh
      3002 # misskey
      3260 # tgt (未使用)
      8000 # gitea
      8384 # syncthing
      9000 # portainer
      10840 # magic_packet_bridge
      18789 # openclaw
      18790 # openclaw bridge
      22000 # syncthing
    ];
    allowedUDPPorts = [
      137 # samba
      138 # samba
      22000 # syncthing
    ];
    # tailnet と podman のネットワークは素通し
    trustedInterfaces = [
      "tailscale0"
      "podman0"
      "podman1"
    ];
  };

  services.tailscale.enable = true;

  virtualisation.podman = {
    enable = true;
    # 既存の compose を docker CLI で扱えるようにする
    dockerCompat = true;
    # portainer / docker-compose が /run/docker.sock を使えるようにする
    # (podman グループのユーザーは root 相当の権限を持つ点に注意)
    dockerSocket.enable = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  users.users.halby.extraGroups = [ "podman" ];

  environment.systemPackages = [ pkgs.docker-compose ];

  # json-file ログでディスクを食いがちなので journald に上限を設ける
  services.journald.extraConfig = ''
    SystemMaxUse=2G
    SystemMaxFileSize=200M
  '';
}
