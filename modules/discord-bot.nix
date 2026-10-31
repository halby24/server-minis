# tomarigi_hp_svelte の Discord デプロイ BOT。
#
# BOT 本体は pkgs/discord-bot でパッケージ化し、デプロイ対象のリポジトリ
# チェックアウト (~/ci/tomarigi_hp_svelte) を作業ディレクトリとして動かす。
# 旧環境は devcontainer 風イメージ + compose で、PHP / pnpm / rsync / ssh を
# 同梱していた。ここではそれらを PATH で提供する。
{ config, lib, pkgs, ... }:
let
  bot = pkgs.callPackage ../pkgs/discord-bot { };
  repoDir = "/home/halby/ci/tomarigi_hp_svelte";

  # packages/web の test:php は phan で、既定の php83 には無い ast 拡張を要求する
  # (無いと "The php-ast extension must be loaded" でビルドが止まる)。
  # 旧 Docker イメージでは pecl で、旧 Ubuntu では mise の setup:php で入れていた。
  php = pkgs.php83.withExtensions ({ enabled, all }: enabled ++ [ all.ast ]);
in
{
  sops.secrets.discord_bot_token = {
    key = "token";
    sopsFile = ../secrets/minis/discord-bot.yaml;
    mode = "0400";
  };

  sops.templates."discord-bot.env" = {
    content = "BOT_TOKEN=${config.sops.placeholder.discord_bot_token}\n";
    owner = "halby";
    mode = "0400";
  };

  systemd.services.discord-bot = {
    description = "Discord deploy bot (tomarigi_hp_svelte)";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    # web の build / deploy スクリプトが使うツール一式
    path = with pkgs; [
      nodejs_22
      pnpm
      php
      php83.packages.composer
      rsync
      openssh
      git
      imagemagick
      bash
      coreutils
      findutils
      gnutar
      gzip
      which
    ];

    environment = {
      HOME = "/home/halby";
      NODE_ENV = "production";
    };

    serviceConfig = {
      User = "halby";
      Group = "users";
      WorkingDirectory = repoDir;
      ExecStart = "${bot}/bin/discord-bot";
      EnvironmentFile = config.sops.templates."discord-bot.env".path;
      Restart = "always";
      RestartSec = "10s";
    };
  };

  systemd.tmpfiles.rules = [
    # ビルド時の画像取得 (tasks/copy-images) とデプロイは、チェックアウト内の
    # .ssh (config / 鍵 / known_hosts) を使って gg へ ssh する。
    # 旧 compose では .ssh を /home/node/.ssh にマウントして HOME 経由で拾わせていたので、
    # その関係を ~/.ssh の symlink で再現する。
    "d ${repoDir}/.ssh 0700 halby users -"
    "L+ /home/halby/.ssh - - - - ${repoDir}/.ssh"

    # 旧 clean-logs コンテナの代替 (1か月より古いログを削除)
    "e ${repoDir}/logs - - - 30d"
    "e ${repoDir}/packages/discord-bot/logs - - - 30d"
  ];
}
