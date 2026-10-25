# restic のバックアップ受け口。
# Windows クライアントから SFTP (sftp:restic@minis:/mnt/data_ssd/restic) で書き込む。
# 既存リポジトリの所有者 (uid/gid 1001) を維持しないと読めなくなるので固定する。
{ pkgs, ... }:
{
  users.groups.restic.gid = 1001;

  users.users.restic = {
    isSystemUser = true;
    uid = 1001;
    group = "restic";
    home = "/home/restic";
    createHome = true;
    shell = pkgs.bash;
    # 旧環境の authorized_keys をそのまま持ってくる
    openssh.authorizedKeys.keyFiles = [ ../keys/restic.pub ];
  };
}
