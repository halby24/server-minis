# コンテナ管理 UI。Portainer の置き換え。
# Cockpit 本体 + cockpit-podman プラグイン (podman ソケット経由で操作)。
#
# 注意: Cockpit のログインは PAM (Unix パスワード) なので、halby に
# Unix パスワードが無いとログインできない。users.mutableUsers = false のため
# `passwd` ではなく secrets/minis/users.yaml のハッシュを更新する (docs/nixos.md)。
{ pkgs, ... }:
{
  services.cockpit = {
    enable = true;
    port = 9090;
    # 9090/tcp を firewall で開ける (LAN 内のみで使う前提)
    openFirewall = true;
    plugins = [ pkgs.cockpit-podman ];
    # motd / issue に Cockpit のバナーを足さない
    showBanner = false;
  };
}
