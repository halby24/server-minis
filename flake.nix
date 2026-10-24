{
  description = "minis (自宅サーバー) の NixOS 構成";

  inputs = {
    # 26.05 が現行の stable。unstable を使う場合はここを差し替える。
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    { nixpkgs, ... }:
    {
      nixosConfigurations = {
        # 実機: AZW MINI S / Intel N100 / x86_64
        minis = nixpkgs.lib.nixosSystem {
          modules = [
            ./modules/common.nix
            ./hosts/minis
          ];
        };

        # 動作確認用 VM。minis 上 (KVM) で動かす想定。
        minis-vm = nixpkgs.lib.nixosSystem {
          modules = [
            ./modules/common.nix
            ./hosts/vm
          ];
        };
      };
    };
}
