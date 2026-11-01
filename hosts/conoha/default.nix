{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware.nix
    ./disk.nix
    ./secrets.nix
    ./caddy.nix
    ./mediamtx.nix
    ./mailpit.nix
  ];

  networking.hostName = "conoha";

  nixpkgs.hostPlatform = "x86_64-linux";

  # 2026-10-31 に Ubuntu 20.04 から移行
  system.stateVersion = "26.05";

  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "ja_JP.UTF-8";

  # --- ネットワーク ---------------------------------------------------------
  # ConoHa は IPv4 も **静的割当**（DHCP は来ない）。旧 netplan と同じ値にする。
  # IF 名は再インストールで変わりうるので MAC アドレスで match する。
  networking.useNetworkd = true;
  networking.useDHCP = false;
  # useNetworkd だけではサービスが enable されないため明示する
  systemd.network.enable = true;
  systemd.network.networks."10-wan" = {
    matchConfig.MACAddress = "fa:16:3e:8a:91:ac";
    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
      IPv6PrivacyExtensions = false;
    };
    address = [
      "160.251.180.206/23"
      "2400:8500:2002:3167:160:251:180:206/64"
    ];
    routes = [
      {
        Destination = "0.0.0.0/0";
        Gateway = "160.251.180.1";
      }
      {
        Destination = "::/0";
        Gateway = "2400:8500:2002:3167::1";
      }
    ];
  };
  networking.nameservers = [
    "150.95.10.8"
    "150.95.10.9"
    "2400:8500:7703:502:150:95:10:8"
    "2400:8500:7703:502:150:95:10:9"
  ];

  # --- ファイアウォール -----------------------------------------------------
  # 旧 ufw の許可ポートを踏襲する。587 (mailpit SMTP) と 1935 (RTMP) は
  # 送信元を絞るので allowedTCPPorts には入れない。
  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22 # ssh
      25 # SMTP (現状は未使用。旧 ufw に合わせて残す)
      80 # caddy (HTTP / ACME)
      443 # caddy
      554 # RTSP (旧設定。現在このポートは未使用)
      8443 # caddy (HTTPS alternate)
      8554 # mediamtx RTSP
      8888 # caddy (HTTPS alternate)
    ];
    allowedUDPPorts = [
      8000 # mediamtx RTP
      8001 # mediamtx RTCP
      41641 # tailscale direct
    ];
    extraInputRules = ''
      # RTMP publish は Tailscale からのみ
      iifname "tailscale0" tcp dport 1935 accept
      # Mailpit SMTP は Tailscale と sakura (www1196) からのみ
      iifname "tailscale0" tcp dport 587 accept
      ip saddr 219.94.129.236 tcp dport 587 accept
    '';
  };

  services.tailscale.enable = true;

  # --- SSH ------------------------------------------------------------------
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "24h";
    jails.DEFAULT.settings.findtime = "10m";
  };

  # --- ユーザー -------------------------------------------------------------
  users.mutableUsers = false;

  users.users.halby = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.bash;
    hashedPasswordFile = config.sops.secrets.halby_password.path;
    openssh.authorizedKeys.keyFiles = [
      ../../keys/halby.pub
      ../../keys/air.pub
      ../../keys/conoha.pub
      ../../keys/halby-desktop.pub
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  # --- Nix ------------------------------------------------------------------
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
    # minis の --build-on remote などで未署名パスをコピーできるように
    trusted-users = [
      "root"
      "halby"
    ];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # RAM が 512MB しかないので swap を必ず持つ
  # (/var/swap は初回起動時に無く mkswap が失敗するため root 直下に置く)
  swapDevices = [
    {
      device = "/swapfile";
      size = 2048;
    }
  ];

  environment.systemPackages = with pkgs; [
    curl
    ffmpeg
    git
    htop
    jq
    rsync
    vim
  ];

  # ログでディスクを食わないように
  services.journald.extraConfig = ''
    SystemMaxUse=1G
    SystemMaxFileSize=100M
  '';

  # ドキュメントは不要 (ディスク節約)
  documentation.enable = false;
}
