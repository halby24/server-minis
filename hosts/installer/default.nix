# リカバリ / USB インストール用の ISO。
# このリポジトリ (flake + 暗号化済み secrets) と disko CLI を焼き込む。
#
# ビルド:
#   nix build .#nixosConfigurations.minis-installer.config.system.build.isoImage
#   → result/iso/nixos-*.iso を USB に dd
{ modulesPath, pkgs, self, disko, ... }:
{
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  nixpkgs.hostPlatform = "x86_64-linux";

  networking.hostName = "minis-installer";

  # リポジトリを /etc/minis-repo に置く (store 経由・読み取り専用)
  environment.etc."minis-repo".source = self.outPath;

  environment.systemPackages = [
    # nixos-anywhere 無しでも USB 単体でフォーマットできるように
    disko.packages.${pkgs.system}.disko
    # 作業用
    pkgs.git
    pkgs.restic
    pkgs.rsync
    pkgs.zstd
  ];

  # リモートからインストールできるように root の SSH 鍵を入れる
  users.users.root.openssh.authorizedKeys.keyFiles = [
    ../../keys/halby.pub
    ../../keys/air.pub
  ];
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "prohibit-password";
  };
}
