# tomarigi_hp_svelte の web ビルド / デプロイ / Discord Bot が使うツール一式。
#
# systemd の PATH と flake の devShell / app の両方から参照する。
# 片方だけ更新されて環境がずれるのを防ぐため、ツールの追加・変更はここだけで行う。
{ pkgs }:
let
  # packages/web の test:php は phan で、既定の php83 には無い ast 拡張を要求する
  # (無いと "The php-ast extension must be loaded" でビルドが止まる)。
  # 旧 Docker イメージでは pecl で、旧 Ubuntu では mise の setup:php で入れていた。
  php = pkgs.php83.withExtensions ({ enabled, all }: enabled ++ [ all.ast ]);
in
{
  inherit php;

  packages = with pkgs; [
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

  shellHook = ''
    echo "minis build shell"
    echo "  node: $(node --version)  pnpm: $(pnpm --version)"
    echo "  php:  $(php -r 'echo PHP_VERSION;')  ast: $(php -m | grep -cx ast)"
    echo "  例: cd ~/ci/tomarigi_hp_svelte && pnpm --filter web run build-dev"
  '';
}
