# misskey (misskey.halby24.com) の compose スタック。
#
# 旧 Ubuntu では docker compose を手で運用していた。ここでは
# compose ファイルを Nix から /etc/misskey/compose.yml に生成し、
# systemd (oneshot) から podman ソケット経由で docker-compose を叩く。
# 設定ファイル (default.yml) は sops のバイナリ秘密として復号し、
# コンテナに read-only でマウントする。
{ config, lib, pkgs, ... }:
let
  dataDir = "/mnt/data_ssd/misskey";
  composeFile = "/etc/misskey/compose.yml";
in
{
  sops.secrets.misskey_default_yml = {
    sopsFile = ../secrets/minis/misskey-default.yml;
    format = "binary";
    # コンテナ内の非 root ユーザーから読めるようにする (bind mount されるため)
    mode = "0444";
  };

  environment.etc."misskey/compose.yml".text = ''
    services:
      web:
        image: docker.io/misskey/misskey:2025.4.0
        restart: unless-stopped
        depends_on:
          db:
            condition: service_healthy
          redis:
            condition: service_healthy
        ports:
          - "127.0.0.1:3002:3002"
        volumes:
          - ${dataDir}/files:/misskey/files
          - ${config.sops.secrets.misskey_default_yml.path}:/misskey/.config/default.yml:ro

      redis:
        image: docker.io/library/redis:7-alpine
        restart: unless-stopped
        volumes:
          - ${dataDir}/redis:/data
        healthcheck:
          test: "redis-cli ping"
          interval: 5s
          retries: 20

      db:
        image: docker.io/library/postgres:15-alpine
        restart: unless-stopped
        volumes:
          - ${dataDir}/db:/var/lib/postgresql/data
        healthcheck:
          test: "pg_isready -U example-misskey-user -d misskey"
          interval: 5s
          retries: 20

      es:
        image: docker.elastic.co/elasticsearch/elasticsearch-oss:6.4.2
        restart: unless-stopped
        environment:
          - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
          - "TAKE_FILE_OWNERSHIP=111"
        volumes:
          - ${dataDir}/elasticsearch:/usr/share/elasticsearch/data
  '';

  systemd.services.misskey = {
    description = "misskey stack (compose via podman)";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "podman.socket"
      "network-online.target"
    ];
    requires = [ "podman.socket" ];
    environment.HOME = "/root";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = "/etc/misskey";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose -f ${composeFile} up -d --remove-orphans";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose -f ${composeFile} down";
    };
  };
}
