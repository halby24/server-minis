# ConoHa VPS を ISO (レスキューモード) から NixOS にするためのインストーラ ISO。
#
# 512MB では nixos-anywhere の kexec が使えないため、ISO 起動でインストールする。
# 対象 (conoha) の system closure を ISO の Nix store に焼き込むので、
# インストール時にネットワークからのダウンロードや評価が不要。
#
# ビルド:
#   nix build .#nixosConfigurations.conoha-installer.config.system.build.isoImage
{ modulesPath, pkgs, self, ... }:
let
  target = self.nixosConfigurations.conoha.config.system.build.toplevel;
in
{
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "conoha-installer";

  # 対象システムの closure を ISO に含める (nixos-install --system 用)
  system.extraDependencies = [ target ];
  environment.etc."conoha-system-path".text = "${target}";

  environment.systemPackages = [
    pkgs.gptfdisk
    pkgs.e2fsprogs
    pkgs.util-linux
    pkgs.rsync
    pkgs.curl
    pkgs.jq
    (pkgs.writeShellScriptBin "conoha-install" ''
      set -euo pipefail

      if [ ! -b /dev/vda ]; then
        echo "ERROR: /dev/vda が見つからない。デバイス名を確認して手動で実行する。" >&2
        exit 1
      fi

      echo "== パーティション作成 (/dev/vda)"
      umount -R /mnt 2>/dev/null || true
      swapoff -a 2>/dev/null || true
      sgdisk --zap-all /dev/vda
      sgdisk -n 1:1MiB:+3MiB -t 1:ef02 -c 1:disk-main-bios /dev/vda
      sgdisk -n 2:0:0 -t 2:8300 -c 2:disk-main-root /dev/vda
      partprobe /dev/vda
      udevadm settle

      echo "== フォーマット / マウント"
      mkfs.ext4 -F -L nixos /dev/vda2
      mount /dev/vda2 /mnt
      mkdir -p /mnt/boot

      # インストール中の保険として 2G の一時 swap (終わったら消す)
      if [ ! -e /mnt/swapfile ]; then
        dd if=/dev/zero of=/mnt/swapfile bs=1M count=2048 status=none
        chmod 600 /mnt/swapfile
        mkswap /mnt/swapfile >/dev/null
      fi
      swapon /mnt/swapfile

      echo "== nixos-install"
      nixos-install --root /mnt --system "$(cat /etc/conoha-system-path)" --no-root-password
      swapoff /mnt/swapfile
      rm -f /mnt/swapfile

      # /root/conoha-data があれば、ホスト鍵と Tailscale state を先に戻す
      if [ -d /root/conoha-data ]; then
        echo "== 退避データを復元"
        install -d -m 0755 /mnt/etc/ssh
        install -m 0600 /root/conoha-data/ssh_host_* /mnt/etc/ssh/
        install -d -m 0700 -o root -g root /mnt/var/lib/tailscale
        cp -a /root/conoha-data/tailscale/. /mnt/var/lib/tailscale/
        chown -R root:root /mnt/var/lib/tailscale
        chmod 0700 /mnt/var/lib/tailscale
      fi

      sync
      echo "INSTALL_OK: アンマウントして unrescue → 起動する"
    '')
  ];

  # レスキューモードで SSH できるようにする
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };
  users.users.root.openssh.authorizedKeys.keyFiles = [
    ../../keys/halby.pub
    ../../keys/air.pub
  ];

  # インストーラ ISO は NetworkManager が DHCP を扱う (CD プロファイル既定)
  networking.firewall.enable = false;

  # コンソールが VNC でも操作しやすいように
  environment.variables = {
    TERM = "xterm-256color";
  };
}
