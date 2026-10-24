# サーバーとしての基本設定。
# 待ち受けポートはここで一元管理し、tailscale と podman を有効にする。
#
# 移行対象外 (2026-10-24 判断):
#   - tgt (iSCSI ターゲット, 3260): ターゲット定義なし。使うなら services.tgt を別途追加する
#   - gitea (8000/2226): リポジトリ 2 件のみで移行しない
#   - openclaw (18789/18790): 移行しない
# 各サービスのポートは、モジュール側で openFirewall を立てられるならそちらに寄せる
# (例: samba は modules/samba.nix の services.samba.openFirewall)。
{ pkgs, ... }:
{
  # 現行 Ubuntu では ufw が無効だったため、ここで初めて明示的な制限をかける。
  # ポートは 2026-10-24 時点で残すサービスに合わせている (docs/current-state.md 参照)。
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      21 # vsftpd (要否は未確認。廃止するなら削除)
      22 # ssh
      3002 # misskey
      8384 # syncthing (web UI)
      9000 # portainer
      10840 # magic_packet_bridge
      22000 # syncthing
    ];
    allowedUDPPorts = [
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
