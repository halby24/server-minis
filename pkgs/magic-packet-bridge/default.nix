# magic_packet_bridge (WoL 中継サーバー) のパッケージ。
# 上流: https://gitlab.halby24.com/halby24/magic_packet_bridge
# 小さいアプリなので、ソースをこのリポジトリに取り込んでいる (MIT)。
{
  lib,
  stdenv,
  nodejs,
  makeWrapper,
  yarnConfigHook,
  fetchYarnDeps,
}:
stdenv.mkDerivation {
  pname = "magic-packet-bridge";
  version = "1.0.0";

  src = ./.;

  offlineCache = fetchYarnDeps {
    yarnLock = ./yarn.lock;
    hash = "sha256-OkNHGdbAW6Id7sVU35m1v2RSphGk5eWr8fN3aQeqyoc=";
  };

  nativeBuildInputs = [
    nodejs
    makeWrapper
    yarnConfigHook
  ];

  buildPhase = ''
    runHook preBuild
    yarn tsc --outDir dist
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib $out/bin
    cp -r dist node_modules package.json $out/lib/
    makeWrapper ${nodejs}/bin/node $out/bin/magic-packet-bridge \
      --add-flags $out/lib/dist/main.js
    runHook postInstall
  '';

  meta = {
    description = "WoL magic packet relay server";
    homepage = "https://gitlab.halby24.com/halby24/magic_packet_bridge";
    license = lib.licenses.mit;
    mainProgram = "magic-packet-bridge";
    platforms = lib.platforms.linux;
  };
}
