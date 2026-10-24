# tomarigi_hp_svelte の Discord デプロイ BOT。
# 上流: https://github.com/TomarigiTei/tomarigi_hp_svelte (private)
# リポジトリ全体はデプロイ用チェックアウトとして実機に置き、
# ここでは BOT 本体 (index.js + discord.js) だけをパッケージ化する。
{
  lib,
  buildNpmPackage,
  nodejs,
  makeWrapper,
}:
buildNpmPackage {
  pname = "discord-bot";
  version = "1.0.0";

  src = ./.;

  npmDepsHash = "sha256-KDkkUITmXTKgDHfJk7QZ0m7A6WovtS9RE0VlWkgC9pw=";

  nativeBuildInputs = [ makeWrapper ];

  # index.js をそのまま実行するだけなのでビルド工程はなし
  dontNpmBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib $out/bin
    cp -r index.js package.json node_modules $out/lib/
    makeWrapper ${nodejs}/bin/node $out/bin/discord-bot \
      --add-flags $out/lib/index.js
    runHook postInstall
  '';

  meta = {
    description = "Discord deploy bot for tomarigi_hp_svelte";
    # 上流は独自ライセンス (LICENSE 参照) のため license は設定しない
    mainProgram = "discord-bot";
    platforms = lib.platforms.linux;
  };
}
