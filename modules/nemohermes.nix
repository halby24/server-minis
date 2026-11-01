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
  # 同じ理由で /bin/ps (forward の所有権確認) と /bin/sleep も必要。
  system.activationScripts.binbash = {
    deps = [ "binsh" ];
    text = ''
      ln -sfn ${pkgs.bashInteractive}/bin/bash /bin/bash
      ln -sfn ${pkgs.procps}/bin/ps /bin/ps
      ln -sfn ${pkgs.coreutils}/bin/sleep /bin/sleep
      # OpenShell の forward 監視は /usr/bin/lsof を直接叩く (NixOS には無い)
      install -d -m 0755 /usr/bin
      ln -sfn ${pkgs.lsof}/bin/lsof /usr/bin/lsof
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

  # OpenCode Go (https://opencode.ai) を推論プロバイダに使うためのヘッダ注入プロキシ。
  #
  # OpenCode Go は x-opencode-session が無いリクエストを 400 MissingSessionID で
  # 拒否する。NemoClaw の検証プローブはカスタムヘッダを送れず、サンドボックスの
  # Hermes 0.21.3 もこのヘッダを送らない (0.21.6 以降)。そこで loopback で受けて
  # ヘッダを足してから upstream へ流す。
  #
  #   Hermes sandbox -> OpenShell -> 127.0.0.1:8000 (nginx) -> opencode.ai
  #
  # 認証ヘッダはそのまま通過させるので、ここに API キーは置かない
  # (キーの実体は OpenShell gateway が保持する)。LAN (192.168/16) と tailnet
  # (100.64/10) からは nginx の allow/deny で拒否する。169.254/16 は
  # サンドボックスが host.openshell.internal 経由で来るときの送信元。
  services.nginx = {
    enable = true;
    appendHttpConfig = ''
      map $http_x_opencode_session $nemohermes_oc_session {
        ""      "ses_nemohermes_minis";
        default $http_x_opencode_session;
      }
    '';
    virtualHosts."nemohermes-opencode" = {
      listen = [
        {
          addr = "0.0.0.0";
          port = 8000;
        }
      ];
      serverName = "nemohermes-opencode";
      locations."/v1/models" = {
        proxyPass = "https://opencode.ai/inference/go/v1/models";
        extraConfig = ''
          allow 127.0.0.1;
          allow 10.0.0.0/8;
          allow 172.16.0.0/12;
          allow 169.254.0.0/16;
          deny all;
          proxy_http_version 1.1;
          proxy_set_header Host opencode.ai;
          # OpenCode 側の Cloudflare は汎用 UA (python-urllib 等) を 1010 で弾く
          proxy_set_header User-Agent "hermes-agent/0.21.3 (nemohermes-proxy)";
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header x-opencode-session $nemohermes_oc_session;
          proxy_ssl_server_name on;
          proxy_buffering off;
        '';
      };
      locations."/v1/" = {
        proxyPass = "https://opencode.ai/inference/go/openai/v1/";
        extraConfig = ''
          allow 127.0.0.1;
          allow 10.0.0.0/8;
          allow 172.16.0.0/12;
          allow 169.254.0.0/16;
          deny all;
          proxy_http_version 1.1;
          proxy_set_header Host opencode.ai;
          # OpenCode 側の Cloudflare は汎用 UA (python-urllib 等) を 1010 で弾く
          proxy_set_header User-Agent "hermes-agent/0.21.3 (nemohermes-proxy)";
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header x-opencode-session $nemohermes_oc_session;
          proxy_ssl_server_name on;
          proxy_buffering off;
          proxy_read_timeout 300s;
        '';
      };
    };
  };

  # nginx 側で LAN / tailnet を弾くので、firewall はコンテナ網からの到達だけ許可する
  networking.firewall.allowedTCPPorts = [ 8000 ];

  # NemoClaw の Podman アダプタは `podman` の realpath から親ディレクトリを辿り、
  # group/other writable なパスを拒否する (executable-authority.ts)。
  # NixOS の podman は /nix/store 配下で、/nix/store は 1775 (nixbld が書ける) ため
  # 必ず失敗する。~/.local/bin に exec するだけの shim を置いて realpath を
  # ストアの外に向ける。
  system.activationScripts.nemohermesPodmanShim.text = ''
    install -d -m 0755 -o halby -g users /home/halby/.local/bin
    cat > /home/halby/.local/bin/podman <<'PODMAN_SHIM'
#!/bin/sh
exec /run/current-system/sw/bin/podman "$@"
PODMAN_SHIM
    chown halby:users /home/halby/.local/bin/podman
    chmod 0755 /home/halby/.local/bin/podman
  '';
}
