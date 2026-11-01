# NVIDIA NemoClaw (nemohermes) のホスト前提。
#
# 本体 (CLI / OpenShell / systemd --user ユニット) はユーザー単位で
#   ~/.local/bin            nemohermes, openshell, openshell-gateway
#   ~/.config/systemd/user  openshell-gateway.service
#   ~/.nemoclaw             レジストリ・サンドボックス定義
# に入る。ここではその前提だけを宣言的に用意する。
#
# サンドボックスは rootless Podman で動かす (Docker は使わない)。
# ports: 18789 dashboard / 8642 OpenAI 互換 API。どちらも loopback バインドなので
#        firewall は開けない。外から見るなら ssh -L で転送する。
{
  pkgs,
  ...
}:
{
  # nemohermes の前提: Node.js >= 22.19 / npm >= 10、strings (binutils)、lsof
  # (すべて installer の preflight が PATH 上で確認する)
  environment.systemPackages = with pkgs; [
    nodejs_22
    binutils
    lsof
  ];

  # openshell-gateway.service など systemd --user のユニットを、
  # ログアウト後・再起動後も動かし続ける
  users.users.halby.linger = true;

  # NemoClaw の CLI は gateway port の解決に /bin/bash をハードコードして
  # spawnSync する (bin/nemoclaw.js)。NixOS の /bin には sh しか無いので足す。
  system.activationScripts.binbash = {
    deps = [ "binsh" ];
    text = ''
      ln -sfn ${pkgs.bashInteractive}/bin/bash /bin/bash
    '';
  };

  # CLI は gateway port が未設定だと `PATH=/usr/bin:/bin` で自分自身の resolver を
  # 呼びに行くが、NixOS の /usr/bin には dirname すら無いため必ず失敗する。
  # 既定値と同じ 8080 を明示して、この経路を踏まないようにする。
  environment.sessionVariables.NEMOCLAW_GATEWAY_PORT = "8080";

  # npm で入る補助バイナリ (prek など) は汎用 Linux 向けの動的リンク ELF なので、
  # NixOS ではそのままでは動かない。nix-ld で ld-linux と基本ライブラリを提供する。
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib
    zlib
    openssl
  ];
}
