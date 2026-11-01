# サーバーとしての基本設定。
# 待ち受けポートはここで一元管理し、tailscale と podman を有効にする。
#
# 移行対象外 (2026-10-24 判断):
#   - tgt (iSCSI ターゲット, 3260): ターゲット定義なし。使うなら services.tgt を別途追加する
#   - gitea (8000/2226): リポジトリ 2 件のみで移行しない
#   - openclaw (18789/18790): 移行しない
#   - vsftpd (21): 廃止 (平文 FTP。SMB / Syncthing で代替)
#   - portainer (9000): Cockpit + cockpit-podman に置き換え (modules/cockpit.nix)
#
# 各サービスのポートは、モジュール側で openFirewall を立てられるならそちらに寄せる
# (例: samba / cockpit)。
{ pkgs, ... }:
{
  # 現行 Ubuntu では ufw が無効だったため、ここで初めて明示的な制限をかける。
  # ポートは残すサービスに合わせて明示している (各モジュールも参照)。
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22 # ssh
      8384 # syncthing (web UI)
      10840 # magic_packet_bridge (使用中)
    ];
    allowedUDPPorts = [ ];
    # misskey (3002) は 127.0.0.1 バインドで cloudflared からのみ届けばよい
    # 22000/tcp・udp と 21027/udp は services.syncthing.openDefaultPorts が開ける
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
    # docker-compose などが /run/docker.sock を使えるようにする
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
