# NixOS 構成

`minis`（自宅サーバー実機）と `conoha`（ConoHa VPS）を 1 つの flake で管理する。
NixOS 26.05 / disko / sops-nix。`stateVersion` は 26.05 固定（上げない）。

## ファイル構成

```
flake.nix                 # nixosConfigurations: minis / minis-vm / minis-test /
                          #   minis-installer / conoha / conoha-installer
modules/common.nix        # 実機・VM 共通（server / secrets / samba / cockpit /
                          #   syncthing / cloudflared / misskey / magic-packet-bridge /
                          #   discord-bot / restic を import）
modules/server.nix        # firewall / tailscale / podman / journald
modules/secrets.nix       # sops-nix (age)
hosts/minis/default.nix   # 実機のホスト設定
hosts/minis/hardware.nix  # カーネルモジュール等（fileSystems は持たない）
hosts/minis/disk.nix      # disko によるディスク構成
hosts/vm/default.nix      # VM 確認用 (qemu-vm, KVM, SSH 2222 転送)
hosts/vm/test_age.key     # VM 専用の age 鍵（ダミー秘密用。公開前提）
hosts/install-test/       # 実機と同じ disko レイアウトの VM rehearsal (minis-test)
hosts/installer/          # USB インストール / リカバリ ISO (minis-installer)
hosts/conoha/             # conoha の構成（OS 再インストールは my-all-servers 側の
                          #   vps/conoha/docs/install.md）
hosts/conoha-installer/   # conoha を ISO レスキューモードから入れる ISO
lib/build-tools.nix       # web ビルド用ツール一式（devShell / app / BOT の PATH で共有）
pkgs/                     # magic-packet-bridge / discord-bot のパッケージ
keys/                     # 各ホストの SSH 公開鍵
.sops.yaml                # sops の暗号化ルール (recipients)
secrets/minis|vm|conoha/  # 暗号化された秘密情報
```

方針: 共通部分は `modules/` に切り出して実機と VM の両方から import する（VM で先に検証するため）。

## ビルド環境

`x86_64-linux` のビルド環境が必要。

- halby-desktop（NixOS VM, 24 cores）か minis 実機でローカルビルドする。
- Mac (arm64) 単体だと linux-builder (aarch64) 経由になり、x86_64 はエミュレーションで遅い。
- conoha は RAM 512MB なのでビルドで OOM しやすい。ビルドは他ホストで行い `nix copy` する。

```sh
nix flake check
nix build .#nixosConfigurations.minis.config.system.build.toplevel --dry-run
```

### web ビルド環境

tomarigi_hp_svelte のビルド・デプロイで使うツールは `lib/build-tools.nix` が正本。
Discord BOT の systemd `path`、`nix develop`、`nix run .#web` の 3 経路が同じ一式を参照する
（片方だけ古くなってビルドが落ちるドリフトを防ぐため）。

```sh
cd ~/minis && nix develop                 # node / pnpm / php+ast / composer / rsync / ssh
cd ~/minis && nix run .#web -- build-dev  # チェックアウトに入って pnpm script を実行
nix run .#web -- deploy-dev               # REPO_DIR で対象チェックアウトを差し替え可
```

phan が要求する `ast` 拡張は既定の `php83` に入っていないので、`php83.withExtensions` で足している。

## ディスク構成 (disko)

`hosts/minis/disk.nix` で宣言。`nixos-anywhere` は disko モジュールを検出して自動で実行する。

| デバイス | パーティション | 内容 |
|---|---|---|
| `/dev/nvme0n1` (476G) | `disk-main-ESP` 1G | vfat → `/boot` (systemd-boot) |
| | `disk-main-swap` 8G | swap (`resumeDevice = false`) |
| | `disk-main-root` 残り | ext4 → `/` |
| `/dev/sda1` (1.8T) | – | 既存 btrfs をラベル `data_ssd` で `/mnt/data_ssd` にマウント（**disko では触らない**） |

- システムディスクは毎回まっさらにする前提。データディスクはフォーマットされない。
- パーティションは `/dev/disk/by-partlabel/disk-main-*` で参照される。
  **ラベルを変えると起動時に emergency mode になる。**
- `hardware.nix` はカーネルモジュール・マイクロコードのみ。実機で採取するときは
  `nixos-generate-config --no-filesystems --root /mnt`（`fileSystems` は disko が持つ）。

```sh
nix build .#nixosConfigurations.minis.config.system.build.diskoScript
head result    # 生成されるパーティション / mkfs / mount スクリプトを確認
```

## 秘密情報 (sops-nix)

暗号化された秘密は `secrets/` に置き、起動時に `/run/secrets/<name>` へ復号される。
実機の復号鍵は **SSH ホスト鍵**（`/etc/ssh/ssh_host_ed25519_key`）なので、追加の鍵配布は不要。

| recipients | 用途 |
|---|---|
| `&minis` / `&conoha` | 各ホストの SSH ホスト鍵から `ssh-to-age` で導出 |
| `&halby` | この Mac の age 鍵（`~/.config/sops/age/keys.txt`）|
| `&vm` | VM テスト専用鍵（`hosts/vm/test_age.key`、公開前提） |

```sh
export SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/keys.txt   # sops 3.13 は自動で拾わない
sops secrets/minis/samba.yaml
```

新しい秘密ファイルを作るときは creation_rules を効かせるためパスを明示する:

```sh
sops --encrypt --input-type yaml --output-type yaml \
  --filename-override secrets/minis/foo.yaml plain.yaml > secrets/minis/foo.yaml
```

- misskey の `default.yml` は**ファイル全体を binary 秘密**にしている。コンテナ（非 root）から
  読めるよう `mode = "0444"` にしてある。
- halby の Unix パスワードは `users.mutableUsers = false` + `hashedPasswordFile`。
  `passwd` では変えられない。変更は sops 更新 + 再ビルド。
  ```sh
  openssl passwd -6          # または nix shell nixpkgs#whois -c mkpasswd -m yescrypt
  sops secrets/minis/users.yaml
  ```
- SMB のパスワード（`secrets/minis/samba.yaml`）とは別物。

## モジュール

### server.nix

- firewall 有効。明示許可は 22 / 8384（Syncthing GUI）/ 10840（magic packet）。
  samba / cockpit / syncthing のデータポートは各モジュールの `openFirewall` 側で開ける。
  misskey の 3002 は `127.0.0.1` バインドなので開けない。
- `tailscale0` と `podman0` / `podman1` は trusted。
- tailscale は `enable` のみ。認証（`tailscale up`）は手動。
- podman は rootless + `dockerCompat` + `dockerSocket.enable`（`/run/docker.sock`）。
  `halby` を `podman` グループに追加（root 相当の権限になる点に注意）。
- journald は `SystemMaxUse=2G` / `SystemMaxFileSize=200M`。
- tgt / gitea / openclaw / vsftpd / portainer は移行対象外（理由はファイル冒頭のコメント）。

### samba.nix

- 共有は `[halby]` = `/home/halby`、`[syncthing]` = `/mnt/data_ssd/syncthing`（`valid users = halby`）。
- パスワードは sops の `samba_halby` を oneshot が `smbpasswd -a -s` で `passdb.tdb` に反映。
  毎起動実行されるが冪等。NixOS 26.05 で `syncPasswordsByPam` が廃止されたためこの方式。

### cockpit.nix

- Portainer の置き換え。`services.cockpit` + `cockpit-podman` でコンテナを管理。
- 9090/tcp（HTTPS・自己署名）。ログインは PAM（Unix パスワード）なので
  `secrets/minis/users.yaml` のハッシュが未設定だとログインできない。

### syncthing.nix

- Docker + host network から `services.syncthing` に置き換え。
- `dataDir` / `configDir` は `/mnt/data_ssd/syncthing`（`config/` 配下が設定）。設定を引き継ぐので
  デバイス ID・フォルダ ID は変わらない。
- `overrideDevices` / `overrideFolders` は `false`。デバイス・フォルダは Web UI (8384) で管理する。
- パスは `lib.mkDefault`。VM では `/home/halby/syncthing` に差し替えている。

### cloudflared.nix

- misskey 公開用。ダッシュボード管理のトンネルを token で起動する（自前 systemd unit）。
  `services.cloudflared` は credentialsFile 前提で token を扱えないため使っていない。
- token は sops (`cloudflared_token`) から `TUNNEL_TOKEN_FILE` で渡す。
- ダッシュボード側の ingress が `http://web:3002` なので `networking.extraHosts` に
  `127.0.0.1 web` を入れている（ingress を `localhost` に変えれば不要）。

### misskey.nix

- compose ファイルを Nix から生成して `/etc/misskey/compose.yml` に置き、systemd (oneshot) が
  `docker-compose up -d` / `down` する。
- イメージは `misskey/misskey:2025.4.0` / `postgres:15-alpine` / `redis:7-alpine` /
  `elasticsearch-oss:6.4.2`。DB のバージョンに合わせて固定してある。
- データは `/mnt/data_ssd/misskey/{db,files,redis,elasticsearch}`。
- 3002 は `127.0.0.1` バインドで cloudflared からのみ届く。
- **バージョンアップは DB マイグレーションを伴うので別作業。**

### magic-packet-bridge.nix

- 自宅の WoL 中継。上流ソースを `pkgs/magic-packet-bridge/` に取り込んでビルド。
- `DynamicUser` で常駐。`LISTEN_PORT=10840` / `MAGIC_PACKET_PORT=2034`。
- `POST http://minis:10840/ {"mac":"..."}` で Magic Packet を送る。

### discord-bot.nix

- tomarigi_hp_svelte の Web デプロイ BOT。本体は `pkgs/discord-bot/` に取り込み、
  `buildNpmPackage` でビルドする。
- 作業ディレクトリは `~/ci/tomarigi_hp_svelte`（チェックアウトと node_modules は stateful）。
- PATH には `lib/build-tools.nix` のツール一式を渡す。
- BOT_TOKEN は sops から `EnvironmentFile` で渡す。
- デプロイ用の鍵 / `config` / `known_hosts` は sops (`secrets/minis/ssh.yaml`) から `~/.ssh` に配る。
  **平文の鍵をチェックアウトに置かない。**
- ログは `<repo>/logs`。systemd-tmpfiles が 30 日より古いものを消す。

### restic.nix

- Windows から `sftp:restic@minis:/mnt/data_ssd/restic` に書き込むバックアップ受け口。
- `restic` ユーザーは **uid/gid 1001 固定**。既存リポジトリの所有者と一致させること。
- 復元には restic のパスワードが別途必要（Windows 側で管理）。手順は [restore-test.md](./restore-test.md)。

## VM での確認

minis は `/dev/kvm` が使えるので KVM で起動する。VM 固有の設定は `hosts/vm/default.nix` の
`virtualisation.vmVariant` に集約（実機の設定を流用し、ハードウェアだけ差し替える）。

```sh
nix build .#nixosConfigurations.minis-vm.config.system.build.vm
./result/bin/run-minis-vm-vm      # kvm グループ権限が必要。SSH は host:2222
```

- コンソールは halby で自動ログイン。`hostfwd` は 0.0.0.0 に開くので**テスト中だけ起動する**。
- ディスクイメージは `minis-vm.qcow2`（sparse、gitignore 済み）。
- 停止は VM 内で `sudo poweroff`、抜けるだけなら `Ctrl-a x`。

disko 構成ごと確認する rehearsal 用ホストもある（実機と同じ GPT、20G イメージ）。

```sh
nix build .#nixosConfigurations.minis-test.config.system.build.vmWithDisko
./result/bin/disko-vm             # SSH は host:2223
```

- misskey / cloudflared は無効、discord-bot はダミートークン。
- disko の `system.build.installTest` はテストディスクが 4G 固定で 8G swap が入らないため使わない。

## インストーラ ISO (minis-installer)

リポジトリ（sops の秘密は暗号化済みなので同梱可）と disko CLI を焼き込んだ
USB インストール / レスキュー用 ISO。

```sh
nix build .#nixosConfigurations.minis-installer.config.system.build.isoImage
ls result/iso/*.iso        # 約 1.5G
```

同梱物: `/etc/minis-repo`（このリポジトリ全体）、`disko` CLI、root の SSH 鍵
（`keys/halby.pub` / `keys/air.pub`）と sshd、`git` / `restic` / `rsync` / `zstd`。

```sh
# インストーラ上で
cd /etc/minis-repo
disko --mode destroy,format,mount --flake .#minis
nixos-install --flake .#minis --root /mnt
```

## 実機の再インストール

**NVMe（システムディスク）は消去され、`/mnt/data_ssd` は残る。**
元の Ubuntu には戻せないので、事前にバックアップとインストーラ USB を用意する。

- ルートディスクは消えるので、`~/.ssh`、`~/ci/tomarigi_hp_svelte`（`.env`）、`~/.config`
  などはデータディスクへ退避する（`rsync -a --exclude node_modules /home/halby/ /mnt/data_ssd/migration-backup/home/`）。
- misskey（Postgres）と syncthing は止めてから電源を切る（データディスクの整合性のため）。

```sh
# 別ホスト（x86_64-linux）から実行する。kexec で対象を再起動するため、対象機の外から
nixos-anywhere --flake .#minis --copy-host-keys halby@<minis>
```

- **`--copy-host-keys` は必須。** sops の age identity を引き継がないと、起動後に秘密が
  すべて復号できなくなる。
- kexec 後のインストーラは DHCP で IP が変わることがある。繋がらないときはルータ側で
  新しい IP を探して接続先を変える。
- 手元で完結させるならインストーラ USB で起動し、上の 2 コマンド + ホスト鍵の復元
  （`cp -a /etc/ssh/ssh_host_* /mnt/etc/ssh/`）。

### 初回起動チェック

```sh
ssh halby@minis
sudo systemctl --failed
sudo ls /run/secrets/            # samba_halby, halby_password など
findmnt /mnt/data_ssd; swapon --show; lsblk
curl -sk -o /dev/null -w '%{http_code}\n' https://127.0.0.1:9090/      # cockpit
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8384/       # syncthing
sudo tailscale up                # 認証は手動
```

### リストア後に直すもの

- **Syncthing のフォルダパス**: データディスクの `config.xml` が旧コンテナ時代のパス
  （`/var/syncthing`）のままだと同期しない。`/mnt/data_ssd/syncthing/...` に直す。
  ```sh
  sudo systemctl stop syncthing
  sudo sed -i 's#/var/syncthing#/mnt/data_ssd/syncthing#g' /mnt/data_ssd/syncthing/config/config.xml
  sudo systemctl start syncthing
  ```
- **デプロイ BOT**: チェックアウトを作り直し、`.env` を退避データから戻して `pnpm install`。
  鍵は sops から配られるのでチェックアウトの `.ssh` は使わない。
- **misskey**: 初回起動でイメージ pull が走る（数分）。DB は `/mnt/data_ssd/misskey/db` をそのまま使う。

## 既知の注意点

- **SSH ホスト鍵 = sops の復号鍵。** 引き継げなかった場合は、新しいホスト鍵を `ssh-to-age` で
  age recipient に変換して `.sops.yaml` に追加し、`sops updatekeys <file>` を実行する。
  復号可否の確認は `ssh-to-age -private-key -i <鍵>` で得た identity を使う
  （`age -d -i <ssh鍵>` は native age recipient には失敗するので判断材料にしない）。
- stateVersion は 26.05 固定。上げない。
- misskey のバージョンアップ（2025.4.0 → 最新）は DB マイグレーションを伴う別作業。
- `nix.gc` は weekly。`system.autoUpgrade` は未設定（必要なら追加）。
- この Mac の `~/.config/sops/age/keys.txt` は 1Password 等に必ず保管する。
