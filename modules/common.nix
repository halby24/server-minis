# 実機と VM で共有する最小設定。
# サービス類は modules/ に増やしていき、両方の host から import する。
{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [ ./server.nix ];

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "26.05";

  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "ja_JP.UTF-8";

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  users.users.halby = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keyFiles = [ ../keys/halby.pub ];
  };
  programs.zsh.enable = true;

  # 現行 minis に合わせてパスワードレス sudo
  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    curl
    git
    htop
    rsync
    vim
  ];
}
