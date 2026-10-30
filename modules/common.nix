# 実機と VM で共有する最小設定。
# サービス類は modules/ に増やしていき、両方の host から import する。
{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./server.nix
    ./secrets.nix
    ./samba.nix
    ./cockpit.nix
    ./syncthing.nix
    ./cloudflared.nix
    ./misskey.nix
    ./magic-packet-bridge.nix
    ./discord-bot.nix
    ./restic.nix
  ];

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

  # Unix アカウントは宣言的に管理する (パスワードは sops のハッシュから設定)
  users.mutableUsers = false;

  users.users.halby = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    hashedPasswordFile = config.sops.secrets.halby_password.path;
    openssh.authorizedKeys.keyFiles = [
      ../keys/halby.pub
      ../keys/air.pub
      ../keys/conoha.pub
      ../keys/halby-desktop.pub
    ];
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
