# Syncthing をネイティブに動かす（旧構成は Docker + host network）。
#
# データと設定は既存のディスク上をそのまま使う（/mnt/data_ssd/syncthing）。
# デバイスやフォルダの追加・削除は Web UI (8384) で行うため、settings では
# overrideDevices / overrideFolders を無効にして既存設定を消さないようにしている。
{ lib, ... }:
{
  services.syncthing = {
    enable = true;
    user = "halby";
    group = "users";
    # 実機はデータディスク上。VM などではホスト側で上書きできるよう mkDefault
    dataDir = lib.mkDefault "/mnt/data_ssd/syncthing";
    configDir = lib.mkDefault "/mnt/data_ssd/syncthing/config";
    guiAddress = "0.0.0.0:8384";
    # 22000/tcp・udp と 21027/udp を開ける (GUI の 8384 は server.nix 側)
    openDefaultPorts = true;
    overrideDevices = false;
    overrideFolders = false;
  };
}
