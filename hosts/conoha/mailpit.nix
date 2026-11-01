# Mailpit (SMTP テストサーバー + Web UI)。
#
# 旧構成は Docker (axllent/mailpit) + DOCKER-USER の iptables 制限だった。
# NixOS では nixpkgs の mailpit を直接動かし、ファイアウォールで送信元を絞る。
# データは /var/lib/mailpit に置く (DynamicUser をやめて静的ユーザーにした)。
{
  config,
  lib,
  ...
}:
{
  services.mailpit.instances.default = {
    database = "mailpit.db";
    max = 5000;
    listen = "0.0.0.0:8025";
    smtp = "0.0.0.0:587";
  };

  users.users.mailpit = {
    isSystemUser = true;
    group = "mailpit";
  };
  users.groups.mailpit = { };

  systemd.services.mailpit-default.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "mailpit";
    Group = "mailpit";

    # 587 (<1024) を bind するため
    AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
    CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];

    # MP_SMTP_AUTH / MP_SMTP_AUTH_ALLOW_INSECURE を sops から読む
    EnvironmentFile = config.sops.secrets.mailpit_env.path;
  };
}
