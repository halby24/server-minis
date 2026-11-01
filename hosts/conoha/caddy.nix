# Caddy + Let's Encrypt (Cloudflare DNS-01)。
#
# 旧構成は Caddy 自身の DNS チャレンジ (cloudflare plugin) で証明書を取っていた。
# NixOS では security.acme (lego) に任せ、Caddy はその証明書ファイルを読む。
# plugin 入り Caddy をビルドしなくて済み、更新は acme のタイマーが行う。
{
  config,
  pkgs,
  ...
}:
let
  domain = "media.halby24.com";

  caddyfile = pkgs.writeText "Caddyfile" ''
    (media) {
      tls /var/lib/acme/${domain}/cert.pem /var/lib/acme/${domain}/key.pem
      encode zstd gzip
      reverse_proxy 127.0.0.1:18080 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
      }
    }

    ${domain} {
      import media
    }

    https://${domain}:8443 {
      import media
    }

    https://${domain}:8888 {
      import media
    }

    :80 {
      respond 404
    }
  '';
in
{
  security.acme = {
    acceptTerms = true;
    certs.${domain} = {
      dnsProvider = "cloudflare";
      environmentFile = config.sops.secrets.cf_dns_token.path;
      group = "caddy";
      reloadServices = [ "caddy" ];
    };
  };

  services.caddy = {
    enable = true;
    configFile = caddyfile;
    adapter = "caddyfile";
    dataDir = "/var/lib/caddy";
    logDir = "/var/log/caddy";
  };

  # 初回起動時に証明書が無くても、acme が自己署名を先に置く。
  # 実証明書の取得完了後に Caddy を起動できるよう順序を付ける。
  systemd.services.caddy = {
    wants = [ "acme-${domain}.service" ];
    after = [ "acme-${domain}.service" ];
  };
}
