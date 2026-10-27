# NixOS 構成 (WIP)

Ubuntu 素朴運用から NixOS + flake に移行するための最小構成。
現状の棚卸しは [current-state.md](./current-state.md) を参照。

## ファイル構成

```
flake.nix                 # nixosConfigurations: minis (実機) / minis-vm (確認用)
modules/common.nix        # 実機・VM 共通の最小設定
modules/server.nix        # firewall / tailscale / podman / journald
modules/cockpit.nix       # Cockpit + cockpit-podman (コンテナ管理 UI)
modules/samba.nix         # Samba の共有とパスワード投入
modules/syncthing.nix     # Syncthing (ネイティブ)
modules/cloudflared.nix   # Cloudflare Tunnel (misskey 公開)
modules/misskey.nix       # misskey の compose スタック (podman)
modules/magic-packet-bridge.nix  # WoL 中継 (systemd)
modules/discord-bot.nix   # Web デプロイ BOT (systemd)
modules/restic.nix        # restic のバックアップ受け口 (restic ユーザー)
modules/secrets.nix       # sops-nix (age) の設定
pkgs/magic-packet-bridge/ # WoL 中継アプリ (上流ソースを取り込み)
pkgs/discord-bot/         # Discord BOT 本体 (index.js + discord.js)
hosts/minis/default.nix   # 実機のホスト設定
hosts/minis/hardware.nix  # カーネルモジュール等 (nixos-generate-config --no-filesystems の出力を反映)
hosts/minis/disk.nix      # disko によるディスク構成
hosts/install-test/       # disko 構成の VM rehearsal 用ホスト (minis-test)
hosts/vm/default.nix      # VM テスト用 (qemu-vm, KVM, SSH 2222 転送)
hosts/vm/test_age.key     # VM 専用の age 鍵 (ダミー秘密用。公開前提)
keys/halby.pub            # halby の SSH 公開鍵 (GitHub の halby24.keys と同一)
.sops.yaml                # sops の暗号化ルール (recipients)
secrets/minis/*.yaml      # 実機用の暗号化された秘密情報
secrets/vm/*.yaml         # VM テスト用 (ダミー)
```

方針:

- 共通部分は `modules/` に切り出し、実機と VM の両方から import する（VM で事前検証するため）。
- 秘密情報は sops-nix + age で暗号化してリポジトリに置く。

## ビルド環境

`x86_64-linux` のビルド環境が必要。

- 実機 minis (Ubuntu) に Nix を入れてビルド・VM 実行する（x86_64 ネイティブ + `/dev/kvm`）。
- Mac (arm64) だけだと linux-builder (aarch64) 経由になり、x86_64 ビルドはエミュレーションで遅い。

### minis に入れた変更 (2026-10-24)

| 内容 | 場所 |
| --- | --- |
| Nix 2.35.4 multi-user install (`nix-daemon` 稼働) | `/nix`, `nix-daemon.service` |
| flakes 有効化 | `~/.config/nix/nix.conf` (`experimental-features = nix-command flakes`) |
| `halby` を `kvm` グループに追加 | `/etc/group` |
| このリポジトリの作業コピー | `~/repos/server/minis` (ローカルから rsync、`.git` は除外) |

シェルから使うときは profile を読む:

```sh
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
nix --version   # nix (Nix) 2.35.4
```

`flake.lock` は nixpkgs `nixos-26.05` (rev `da6dc0e`) で固定済み。

```sh
nix flake check
nix build .#nixosConfigurations.minis.config.system.build.toplevel --dry-run
```

## VM で動作確認

minis は `/dev/kvm` が使えるので KVM で起動する。
VM 固有の設定は `hosts/vm/default.nix` の `virtualisation.vmVariant` に集約している
(実機の設定をそのまま流用し、仮想ハードウェアだけ差し替えるため)。

```sh
nix build .#nixosConfigurations.minis-vm.config.system.build.vm
./result/bin/run-minis-vm-vm    # kvm グループ権限が必要
```

確認済み (2026-10-24):

- `nix flake check` は全チェック通過。
- NixOS 26.05 (`26.05.20261021.da6dc0e`), kernel 6.18.57 で起動。`/` は `/dev/vda` (ext4)、`/nix/store` はホストの store を 9p + overlay でマウント。
- `ssh -p 2222 halby@<minis>` でログインでき、`wheel` グループ + パスワードレス sudo が効く。
- コンソールは halby で自動ログイン (初回は `zsh-newuser-install` のメニューが出る)。
- `hostfwd` は全インターフェースに開く (0.0.0.0:2222)。テスト中だけ起動する。
- ディスクイメージはリポジトリ直下の `minis-vm.qcow2` (sparse, gitignore 済み)。
- `hosts/vm/default.nix` には flake check を通すためのダミー root (`/dev/vda`) を置いてあり、VM 起動時は qemu-vm が上書きする。

サービスを増やすときは `modules/` に切り出して共通化し、VM で先に確認する。

停止は VM 内で `sudo poweroff`。抜けるだけなら `Ctrl-a x`。

## サーバー基本設定 (modules/server.nix)

- **firewall**: 有効化。残すサービスのポートを明示許可 (22, 8384, 10840)。Samba は `services.samba.openFirewall` で 139/445/tcp・137-138/udp、Cockpit は `services.cockpit.openFirewall` で 9090/tcp、Syncthing は `openDefaultPorts` で 22000/tcp・udp と 21027/udp を開く。`tailscale0` と `podman0`/`podman1` は trusted。misskey の 3002 は 127.0.0.1 バインドなので開放しない。
- **移行対象外**: tgt (iSCSI, 3260) / gitea (8000, 2226) / openclaw (18789-18790) / vsftpd (21, 廃止) / portainer (9000, Cockpit に置換)。理由は `modules/server.nix` 冒頭に記載。
- **残すもの**: misskey (3002), syncthing (8384, 22000), magic_packet_bridge (10840, 使用中), samba, cockpit。
- **tailscale**: `services.tailscale.enable` のみ。認証 (`tailscale up`) は手動で行う。
- **podman**: rootless 既定 + `dockerCompat` (docker CLI シム) + `dockerSocket.enable` (`/run/docker.sock` → podman ソケット)。`halby` を `podman` グループに追加（root 相当の権限を持つ点に注意）。`docker-compose` (v5.4.0) も導入。
- **journald**: `SystemMaxUse=2G`, `SystemMaxFileSize=200M`。

VM で確認済み (2026-10-24):

- `firewall.service` active、iptables に許可ポートが入る
- `tailscaled` active（未ログイン状態）
- `podman info` が rootless で動作、`/etc/subuid` は自動採番
- `/run/docker.sock` 経由で `docker ps` / `docker run` / `docker-compose up` が動作（nginx を起動して HTTP 200 を確認）

## 秘密情報 (sops-nix)

- 暗号化された秘密は `secrets/` に置き、`sops-nix` が起動時に `/run/secrets/<name>` へ復号する。
- 実機の復号鍵は **SSH ホスト鍵** (`/etc/ssh/ssh_host_ed25519_key`)。追加の鍵ファイル配布が不要。
- `.sops.yaml` の recipient:
  - `&minis`: 現行 minis の SSH ホスト鍵から `ssh-to-age` で導出
    (`age1lytk9qynst8c0ganxrt68vvmsf9h93l9nfueh85t2razr7ksdeaqv9j6xc`)
  - `&halby`: この Mac の age 鍵 (`~/.config/sops/age/keys.txt`)
  - `&vm`: VM テスト専用鍵 (`hosts/vm/test_age.key`、リポジトリに公開されている)
- VM は `system.activationScripts.vmAgeKey` で上記テスト鍵を `/var/lib/sops-nix/key.txt` に置き、
  `setupSecrets` より先に実行されるようにしている。復号できるのはダミー秘密のみ。

### 編集方法

Mac 側のツール (`brew install sops age`) と鍵が必要。sops 3.13 は既定で
`~/.config/sops/age/keys.txt` を拾わなかったため、環境変数で明示する。

```sh
export SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/keys.txt
sops secrets/minis/samba.yaml          # エディタで編集
```

新しい秘密ファイルを作るときは creation_rules を効かせるためパスを明示する。

```sh
sops --encrypt --input-type yaml --output-type yaml \
  --filename-override secrets/minis/foo.yaml plain.yaml > secrets/minis/foo.yaml
```

### halby の Unix パスワード

`users.mutableUsers = false` にし、`users.users.halby.hashedPasswordFile` に sops で復号した
ハッシュを渡している (`neededForUsers = true` により `/run/secrets-for-users/halby_password`)。

- `passwd` による変更はできない。パスワード変更は sops の更新 + 再ビルドで行う。
- SMB のパスワード (`secrets/minis/samba.yaml`) とは別物。

```sh
# ハッシュ生成 (パスワードを2回入力)
openssl passwd -6
# yescrypt にしたい場合: nix shell nixpkgs#whois -c mkpasswd -m yescrypt

sops secrets/minis/users.yaml   # halby: に $6$... / $y$... を貼る
```

現在 `secrets/minis/users.yaml` は `!`（ロック）のプレースホルダ。設定するまで
Cockpit などのパスワードログインはできない（SSH は鍵認証のみなので影響なし）。

### 実機インストール時の注意

- ホスト鍵を引き継がないと復号できない。`nixos-anywhere` でホスト鍵をコピーするか、
  インストール後に新しい公開鍵を `ssh-to-age` で変換して `.sops.yaml` に追加し、
  `sops updatekeys <file>` を実行する。
- `secrets/minis/samba.yaml` の `halby` は SMB のパスワード（設定済み）。
- `secrets/minis/users.yaml` の `halby` は Unix パスワードのハッシュ。未設定 (`!`) のままデプロイすると
  Cockpit にログインできないので、事前に設定しておく。

## Samba (modules/samba.nix)

- 共有: `[halby]` = `/home/halby`, `[syncthing]` = `/mnt/data_ssd/syncthing`（どちらも `valid users = halby`）。
- `security = user` / `map to guest = bad user`、`openFirewall = false`（firewall は server.nix 側）。
- パスワードは sops の `samba_halby` を読み、`systemd.services.samba-password` (oneshot) が
  `smbpasswd -a -s halby` で `passdb.tdb` に反映する。毎起動で実行されるが冪等。
- NixOS 26.05 では `services.samba.syncPasswordsByPam` が廃止されているため、この方式にしている。

VM で確認済み (2026-10-24):

- sops の復号 (`/run/secrets/samba_halby`) と `samba-password.service` の成功
- 正しいパスワードで `smbclient //127.0.0.1/halby -U halby%test1234` がディレクトリ一覧を返す
- 誤ったパスワードは `NT_STATUS_LOGON_FAILURE`

## Cockpit (modules/cockpit.nix)

Portainer の置き換え。`services.cockpit` + `cockpit-podman` プラグインでコンテナを管理する。

- 9090/tcp (HTTPS, 自己署名証明書)。`openFirewall = true` で LAN に開く。
- cockpit-podman は system の podman ソケット経由でコンテナ / イメージ / ボリュームを操作する。
- **ログインは PAM (Unix パスワード)**。パスワードは sops の `halby_password` から
  `hashedPasswordFile` 経由で設定する（[halby の Unix パスワード](#halby-の-unix-パスワード) 参照）。

VM で確認済み (2026-10-24):

- `cockpit.socket` が active、9090 を listen、`curl -k https://127.0.0.1:9090/` が 200
- sops のハッシュが `/etc/shadow` に入り、PAM (`su`) でパスワード認証できる
- `GET /cockpit/login` + Basic 認証で 200 とセッション cookie が返る（誤パスワードは 401）
- cockpit の plugin 一覧に `podman` が含まれる
- `podman.socket` が active
- firewall に 9090 が入り、21 / 9000 が消えている

## Syncthing (modules/syncthing.nix)

Docker + host network で動かしていたものを `services.syncthing` に置き換え。

- `user = "halby"`、`dataDir` / `configDir` は既存の `/mnt/data_ssd/syncthing`（設定は `config/` 配下）。
  設定を引き継ぐのでデバイス ID とフォルダ ID は変わらない。
- `guiAddress = "0.0.0.0:8384"`（firewall は server.nix）、`openDefaultPorts = true`。
- デバイス・フォルダの追加は Web UI で行うため `overrideDevices` / `overrideFolders` は `false`
  にしてある（Nix 側で既存設定が消されないように）。
- パスは `lib.mkDefault` にしてあり、VM では `/home/halby/syncthing` に差し替えている。

VM で確認済み (2026-10-24): `syncthing` active、8384/22000 を listen、GUI が 200、`config.xml` を自動生成。

## Cloudflare Tunnel (modules/cloudflared.nix)

misskey の公開経路。既存のダッシュボード管理トンネルをそのまま使う。

- `services.cloudflared` は credentialsFile 前提で token を扱えないため、自前の systemd unit を定義。
- トークンは sops (`secrets/minis/cloudflared.yaml` → `/run/secrets/cloudflared_token`)。
  旧 compose の `TUNNEL_TOKEN` を移したもの。`TUNNEL_TOKEN_FILE` で渡す。
- 実行ユーザーは `cloudflared` (system user)。ingress はダッシュボード側 (`http://localhost:3002`)。
- misskey 本体はまだ compose のままなので、3002 の公開は別途 podman 化が必要。

VM で確認済み (2026-10-24): unit が起動し、ダミートークンを読んで
「Provided Tunnel token is not valid」で失敗するところまで（配線の確認）。実接続はデプロイ後。

## Misskey (modules/misskey.nix)

旧環境では手運用の docker compose だったものを、compose ファイルを Nix から生成して
systemd (oneshot) から podman ソケット経由で起動する構成にした。

- compose は `/etc/misskey/compose.yml` に生成。`systemd.services.misskey` が
  `docker-compose up -d` / `down` を実行する。
- イメージ: `misskey/misskey:2025.4.0`（旧環境はローカルビルド。DB のバージョンに合わせて固定）、
  `postgres:15-alpine`、`redis:7-alpine`、`elasticsearch-oss:6.4.2`。
- データ: `/mnt/data_ssd/misskey/{db,files,redis,elasticsearch}`。
  `db` と `files` は既存。`redis` / `elasticsearch` は新規（旧環境では `~/servers/misskey` 配下、
  redis 5.7M / ES 24K だったのでキャッシュとして作り直す）。
- 設定 `default.yml` は **ファイル全体を sops の binary 秘密**として持つ
  (`secrets/minis/misskey-default.yml` → `/run/secrets/misskey_default_yml`)。コンテナには read-only でマウント。
- 3002 は `127.0.0.1:3002` にバインドし、cloudflared からのみ到達させる（firewall では開放しない）。
- バージョンアップ（2025.4.0 → 最新）は DB マイグレーションを伴うので別作業。

binary 秘密の編集:

```sh
sops --decrypt --input-type binary --output-type binary secrets/minis/misskey-default.yml > /tmp/default.yml
$EDITOR /tmp/default.yml
sops --encrypt --input-type binary --output-type binary \
  --filename-override secrets/minis/misskey-default.yml /tmp/default.yml > secrets/minis/misskey-default.yml
```

確認済み (2026-10-25): 生成した compose が `docker compose config` を通る（web/db/redis/es）、
VM で sops の binary 秘密が復号されて `/run/secrets/misskey_default_yml` に展開される。
スタック自体はデータディスク前提なので VM では起動していない（実機デプロイ後に確認）。

## Magic Packet Bridge (modules/magic-packet-bridge.nix)

自宅の WoL 中継サーバー。旧環境は devcontainer イメージ + host network の compose。

- アプリは上流 (gitlab.halby24.com) のソースを `pkgs/magic-packet-bridge/` に取り込んでビルド
  (`yarn` + `tsc`、`fetchYarnDeps` の hash を固定)。
- `systemd.services.magic-packet-bridge` として `DynamicUser` で常駐させる。
- 環境変数は旧 `.env.production` と同じ (`LISTEN_PORT=10840`, `MAGIC_PACKET_PORT=2034`)。
- 10840/tcp は `modules/server.nix` で許可。

VM で確認済み (2026-10-25): サービス active、10840 を listen、
`POST / {"mac":"FFFFFFFFFFFF"}` が「送信に成功しました」を返す。

## Discord デプロイ BOT (modules/discord-bot.nix)

tomarigi_hp_svelte の Web デプロイ BOT。旧環境は devcontainer 風イメージ + compose。

- BOT 本体 (`index.js` + discord.js 14.13.0) は `pkgs/discord-bot/` に取り込み、
  `buildNpmPackage` でビルドする。
- 対象リポジトリのチェックアウト (`~/ci/tomarigi_hp_svelte`) を作業ディレクトリにして
  `pnpm --filter web <command>` を実行する。チェックアウトと node_modules は stateful。
- PATH に nodejs_22 / pnpm / php83 / composer / rsync / openssh / git / imagemagick などを渡す
  (旧イメージに同梱していたツール一式)。
- BOT_TOKEN は sops (`secrets/minis/discord-bot.yaml`) から
  `/run/secrets/rendered/discord-bot.env` を生成して `EnvironmentFile` で渡す。
- ログは `<repo>/logs` と `<repo>/packages/discord-bot/logs`。旧 clean-logs コンテナの代わりに
  systemd-tmpfiles で 30 日より古いファイルを削除。
- デプロイ用の SSH 鍵は halby の `~/.ssh` を使う（deploy.sh はホスト実行時そのユーザーの鍵を使う設計）。

VM で確認済み (2026-10-25): サービスが起動し、ダミートークンで `TokenInvalid` になるところまで
（パッケージ・env ファイル・作業ディレクトリの配線確認）。Discord 接続と実デプロイは実機デプロイ後。

## バックアップ受け口 (modules/restic.nix)

Windows クライアントから `sftp:restic@minis:/mnt/data_ssd/restic` に restic で書き込む構成。

- `restic` ユーザーを **uid/gid 1001 固定**で作る。既存リポジトリの所有者が 1001 のため、
  変えるとリポジトリを読めなくなる。
- `~/.ssh/authorized_keys` は旧環境の内容をそのまま `keys/restic.pub` として取り込み。
- リポジトリは `/mnt/data_ssd/restic`（disko は触らない）。SFTP は sshd の既定サブシステム。
- 復元・確認は restic のパスワードが別途必要（Windows 側で管理）。

## リカバリ / インストーラ ISO (minis-installer)

flake に `nixosConfigurations.minis-installer` を追加してある。リポジトリと disko CLI を
焼き込んだ USB インストール / レスキュー用 ISO。

```sh
nix build .#nixosConfigurations.minis-installer.config.system.build.isoImage
ls result/iso/*.iso        # 約 1.5G
```

同梱物:

- `/etc/minis-repo` に**このリポジトリ全体**（sops の秘密は暗号化済みなので同梱可）
- `disko` CLI（`nixos-anywhere` 無しでも USB 単体でフォーマット可能）
- root の SSH 鍵（`keys/halby.pub`）と sshd
- `git` / `restic` / `rsync` / `zstd`

USB からのインストール例（インストーラ上で）:

```sh
cd /etc/minis-repo
disko --mode destroy,format,mount --flake .#minis
nixos-install --flake .#minis --root /mnt
```

> 既存システムの上に再インストールする場合は、`/etc/ssh/ssh_host_*` を退避しておき
> `/mnt/etc/ssh/` に戻すこと（sops の復号鍵を維持するため）。

## ディスク構成 (disko)

`hosts/minis/disk.nix` で宣言。`nixos-anywhere` は disko モジュールを検出して自動で実行する。

| デバイス | パーティション | 内容 |
| --- | --- | --- |
| `/dev/nvme0n1` (476G) | `disk-main-ESP` 1G | vfat → `/boot` (systemd-boot) |
| | `disk-main-swap` 8G | swap (`resumeDevice = false`) |
| | `disk-main-root` 残り | ext4 → `/` |
| `/dev/sda1` (1.8T) | – | 既存 btrfs をラベル `data_ssd` で `/mnt/data_ssd` にマウント（**disko では触らない**） |

- システムディスクは毎回まっさらにする前提。データディスクはフォーマットされない。
- パーティションは `/dev/disk/by-partlabel/disk-main-*` で参照される。
- `hardware.nix` はカーネルモジュール・マイクロコードのみを持ち、`fileSystems` は disko 側へ移動した。
  実機で採取するときは `nixos-generate-config --no-filesystems --root /mnt`。

確認:

```sh
nix build .#nixosConfigurations.minis.config.system.build.diskoScript
head result    # 生成されるパーティション / mkfs / mount スクリプト

nix eval --json .#nixosConfigurations.minis.config.fileSystems --apply builtins.attrNames
# ["/","/boot","/mnt/data_ssd"]
```

確認済み (2026-10-24): `fileSystems = [ "/" "/boot" "/mnt/data_ssd" ]`、
`swapDevices = [ "/dev/disk/by-partlabel/disk-main-swap" ]`、disko スクリプトに
`mkfs.vfat` / `mkswap` / `mkfs.ext4` と `/mnt` `/mnt/boot` へのマウントが出力される。

## VM でのインストール rehearsal (hosts/install-test)

実機と同じ disko レイアウトでディスクイメージを作り、そこから起動する rehearsal 用の構成
`minis-test` を用意した。

- `hosts/install-test/disk.nix`: 実機と同じ GPT (ESP 1G / swap 8G / root 残り)
- `hosts/install-test/default.nix`: 実機のモジュール一式 + テスト用の秘密・パス・無効化
  - sops は `hosts/vm/test_age.key` で復号
  - データディスクが無いので syncthing は `/home/halby/syncthing`
  - misskey / cloudflared は無効、discord-bot はダミートークン
  - `disko.devices.disk.main.imageSize = "20G"`、`disko.memSize = 4096`

```sh
nix build .#nixosConfigurations.minis-test.config.system.build.vmWithDisko
./result/bin/disko-vm        # kvm グループ権限が必要 (SSH は host:2223 に転送)
```

結果 (2026-10-25、成功):

- disko が作ったディスクから起動: `vda1` 1G vfat `/boot`、`vda2` 8G swap (有効)、`vda3` 11G ext4 `/`
- sops の秘密が復号され `/run/secrets/{cloudflared_token,discord_bot_token,misskey_default_yml,samba_halby}` が生成
- `samba-smbd` / `samba-nmbd` / `samba-winbindd` 稼働、`smbclient` で共有一覧 (`halby`, `syncthing`)
- Cockpit 9090 が 200、Syncthing 8384 が 200、magic_packet_bridge が Magic Packet 送信成功
- discord-bot はダミートークンで再起動ループ (想定どおり)、misskey は無効、`systemctl --failed` なし

補足: disko の `system.build.installTest` はテスト用ディスクが 4G 固定で 8G swap が入らないため使わず、
`vmWithDisko` (20G イメージ) で確認している。

## 実機投入 (未実施)

前提: 事前にバックアップ（現状 restic は 6 月から停止しているので注意）。
**NVMe は disko で初期化される**（データディスク `/mnt/data_ssd` は対象外）。

```sh
# ハードウェア情報の採取（fileSystems は disko が持つので不要）
nixos-generate-config --no-filesystems --root /mnt

# 別マシン (x86_64-linux) から実行する。ホスト鍵を引き継ぐこと (sops の復号鍵)
nixos-anywhere --flake .#minis --copy-host-keys root@192.168.2.130
```

注意点:

- **nixos-anywhere は対象機の外から実行する**必要がある（kexec で対象を再起動するため）。
  minis 自身を対象にするなら conoha など別ホストから。手元で完結させるなら
  NixOS インストーラ USB で起動して
  `disko --mode destroy,format,mount --flake .#minis` → `nixos-install --flake .#minis --root /mnt`。
- `--copy-host-keys` を忘れると、sops の age identity（SSH ホスト鍵）が変わり復号できなくなる。
  その場合は新しいホスト鍵を `ssh-to-age` で変換して `.sops.yaml` に追加し、`sops updatekeys` する。
- `/mnt/data_ssd` は別ディスクなので、NVMe 側だけ入れ替えればデータは残せる。
- stateVersion は 26.05 固定（移行後に上げない）。
- インストール後の確認: `sudo getent shadow halby`（sops のハッシュ）、Cockpit (9090) のログイン、
  `systemctl --failed`。
