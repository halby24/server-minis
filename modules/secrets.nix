# sops-nix の設定。秘密情報は secrets/ 以下に age で暗号化して置く。
# 実機では SSH ホスト鍵を age identity として使う（鍵ファイルの追加配布が不要）。
{ ... }:
{
  sops = {
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      samba_halby = {
        key = "halby";
        sopsFile = ../secrets/minis/samba.yaml;
        owner = "root";
        mode = "0400";
      };

      # halby の Unix パスワード (crypt ハッシュ)。
      # neededForUsers = true で users の activation より前に復号される。
      halby_password = {
        key = "halby";
        sopsFile = ../secrets/minis/users.yaml;
        neededForUsers = true;
      };
    };
  };
}
