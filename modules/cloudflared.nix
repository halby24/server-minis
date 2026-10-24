# Cloudflare Tunnel (misskey の公開経路: https://misskey.halby24.com)。
#
# 既存のダッシュボード管理トンネルをそのまま使うため、token で起動する。
# NixOS の services.cloudflared は credentialsFile 前提なので使わず、
# token を sops から読む systemd unit を自前で定義している。
{ config, lib, pkgs, ... }:
{
  users.users.cloudflared = {
    isSystemUser = true;
    group = "cloudflared";
  };
  users.groups.cloudflared = { };

  sops.secrets.cloudflared_token = {
    key = "token";
    sopsFile = ../secrets/minis/cloudflared.yaml;
    owner = "cloudflared";
    mode = "0400";
  };

  systemd.services.cloudflared-misskey = {
    description = "Cloudflare Tunnel for misskey";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      # ingress はダッシュボード側 (remote-managed) の設定が使われる
      ExecStart = "${lib.getExe pkgs.cloudflared} tunnel --no-autoupdate run";
      Environment = "TUNNEL_TOKEN_FILE=${config.sops.secrets.cloudflared_token.path}";
      User = "cloudflared";
      Group = "cloudflared";
      Restart = "always";
      RestartSec = "5s";
      # 書き込みは不要
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };
}
