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
  # devShell / app と同じツール一式 (lib/build-tools.nix が正本)
  tools = import ../lib/build-tools.nix { inherit pkgs; };
in
{
  sops.secrets = {
    discord_bot_token = {
      key = "token";
      sopsFile = ../secrets/minis/discord-bot.yaml;
      mode = "0400";
    };

    # ビルド時の画像取得 (tasks/copy-images) と deploy.sh は ~/.ssh の
    # config / 鍵 / known_hosts を使って gg へ ssh する。
    # 旧 compose ではリポジトリの .ssh を /home/node/.ssh にマウントしていたが、
    # 平文の鍵をチェックアウトに置かないよう sops から配る。
    ssh_id_ed25519 = {
      key = "id_ed25519";
      sopsFile = ../secrets/minis/ssh.yaml;
      path = "/home/halby/.ssh/id_ed25519";
      owner = "halby";
      group = "users";
      mode = "0400";
    };
    ssh_config = {
      key = "config";
      sopsFile = ../secrets/minis/ssh.yaml;
      path = "/home/halby/.ssh/config";
      owner = "halby";
      group = "users";
      mode = "0400";
    };
    ssh_known_hosts = {
      key = "known_hosts";
      sopsFile = ../secrets/minis/ssh.yaml;
      path = "/home/halby/.ssh/known_hosts";
      owner = "halby";
      group = "users";
      mode = "0644";
    };
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

    # web の build / deploy スクリプトが使うツール一式 (devShell と共通)
    path = tools.packages;

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
    # sops が鍵を書き込む先。ssh クライアント設定の慣例どおり 0700 にしておく。
    "d /home/halby/.ssh 0700 halby users -"

    # 旧 clean-logs コンテナの代替 (1か月より古いログを削除)
    "e ${repoDir}/logs - - - 30d"
    "e ${repoDir}/packages/discord-bot/logs - - - 30d"
  ];
}
