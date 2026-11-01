# sops-nix。ホストの SSH ホスト鍵を age identity に使う（minis と同じ方式）。
# nixos-anywhere では --copy-host-keys を必ず付けること。
{ ... }:
{
  sops = {
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      # Cloudflare DNS-01 用。中身は CF_DNS_API_TOKEN=... の 1 行
      cf_dns_token = {
        key = "cf_dns_token";
        sopsFile = ../../secrets/conoha/cloudflare.yaml;
      };

      # mailpit の SMTP AUTH 設定 (EnvironmentFile 形式)
      mailpit_env = {
        key = "mailpit_env";
        sopsFile = ../../secrets/conoha/mailpit.yaml;
      };

      # halby の Unix パスワード (crypt ハッシュ)
      halby_password = {
        key = "halby";
        sopsFile = ../../secrets/conoha/users.yaml;
        neededForUsers = true;
      };
    };
  };
}
