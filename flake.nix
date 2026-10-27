{
  description = "minis (自宅サーバー) の NixOS 構成";

  inputs = {
    # 26.05 が現行の stable。unstable を使う場合はここを差し替える。
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, sops-nix, disko, ... }:
    {
      packages.x86_64-linux = {
        magic-packet-bridge =
          nixpkgs.legacyPackages.x86_64-linux.callPackage ./pkgs/magic-packet-bridge { };
        discord-bot = nixpkgs.legacyPackages.x86_64-linux.callPackage ./pkgs/discord-bot { };
      };

      nixosConfigurations = {
        # リカバリ / USB インストール用 ISO
        minis-installer = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit self disko; };
          modules = [ ./hosts/installer ];
        };
        # 実機: AZW MINI S / Intel N100 / x86_64
        minis = nixpkgs.lib.nixosSystem {
          modules = [
            sops-nix.nixosModules.sops
            disko.nixosModules.disko
            ./modules/common.nix
            ./hosts/minis
          ];
        };

        # 動作確認用 VM。minis 上 (KVM) で動かす想定。
        # ディスクは qemu-vm が用意するので disko は使わない。
        minis-vm = nixpkgs.lib.nixosSystem {
          modules = [
            sops-nix.nixosModules.sops
            ./modules/common.nix
            ./hosts/vm
          ];
        };

        # disko 構成の rehearsal 用 (実機と同じレイアウトで VM を作る)
        minis-test = nixpkgs.lib.nixosSystem {
          modules = [
            sops-nix.nixosModules.sops
            disko.nixosModules.disko
            ./modules/common.nix
            ./hosts/install-test
          ];
        };
      };
    };
}
