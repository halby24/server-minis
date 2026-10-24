# Samba の共有設定。パスワードは sops の secret から投入する。
{ config, lib, pkgs, ... }:
{
  services.samba = {
    enable = true;
    # 139/445/tcp と 137-138/udp を firewall で開ける
    openFirewall = true;
    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "minis";
        "server role" = "standalone server";
        security = "user";
        "map to guest" = "bad user";
        "log file" = "/var/log/samba/log.%m";
        "max log size" = "1000";
        logging = "file";
      };
      halby = {
        path = "/home/halby";
        browseable = "yes";
        writable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "halby";
      };
      syncthing = {
        path = "/mnt/data_ssd/syncthing";
        browseable = "yes";
        writable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "halby";
      };
    };
  };

  # sops で復号したパスワードを Samba のパスワード DB (passdb.tdb) に反映する。
  # 毎回の起動で実行されるが冪等 (同じ値を入れ直すだけ)。
  systemd.services.samba-password = {
    description = "Apply Samba password for halby from sops secret";
    wantedBy = [ "multi-user.target" ];
    after = [ "samba.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      pw="$(cat ${config.sops.secrets.samba_halby.path})"
      if [ -z "$pw" ] || [ "$pw" = "CHANGE_ME" ]; then
        echo "samba: sops の samba_halby が未設定です (secrets/minis/samba.yaml)" >&2
        exit 1
      fi
      { echo "$pw"; echo "$pw"; } | ${pkgs.samba}/bin/smbpasswd -a -s halby
    '';
  };
}
