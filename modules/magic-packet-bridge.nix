# Magic Packet Bridge (WoL 中継)。旧環境では docker compose (host network) で
# devcontainer イメージ上の ts-node を動かしていた。
# ここでは pkgs/magic-packet-bridge としてビルドし、systemd で直接動かす。
{ pkgs, ... }:
let
  pkg = pkgs.callPackage ../pkgs/magic-packet-bridge { };
in
{
  systemd.services.magic-packet-bridge = {
    description = "Magic Packet Bridge (WoL relay)";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      ExecStart = "${pkg}/bin/magic-packet-bridge";
      # 旧 .env.production と同じ値
      Environment = [
        "NODE_ENV=production"
        "LISTEN_PORT=10840"
        "MAGIC_PACKET_PORT=2034"
      ];
      DynamicUser = true;
      Restart = "always";
      RestartSec = "5s";
    };
  };
}
