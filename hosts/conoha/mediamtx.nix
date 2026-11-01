# MediaMTX (RTSP / RTMP / HLS / WebRTC / SRT)。
# nixpkgs に NixOS モジュールが無いので systemd サービスを直接書く。
# 設定ファイルに秘密は無い (認証は送信元 IP で制御) ので /etc に置く。
{ pkgs, ... }:
{
  environment.etc."mediamtx/mediamtx.yml".source = ./mediamtx.yml;

  systemd.services.mediamtx = {
    description = "MediaMTX media server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      ExecStart = "${pkgs.mediamtx}/bin/mediamtx /etc/mediamtx/mediamtx.yml";
      Restart = "on-failure";
      RestartSec = 5;

      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
        "AF_NETLINK" # webrtcIPsFromInterfaces のインターフェース列挙に必要
      ];
      RestrictNamespaces = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
    };
  };
}
