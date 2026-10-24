{
  imports = [ ./hardware.nix ];

  networking.hostName = "minis";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.useDHCP = true;
}
