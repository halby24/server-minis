# minis 移行手順書 (Ubuntu → NixOS)

2026-10-25 時点の構成に基づく実機投入の手順。**NVMe (システムディスク) は消去され、
データディスク (`/mnt/data_ssd`, 1.8T btrfs) はそのまま残る**前提。

関連: [current-state.md](./current-state.md) / [nixos.md](./nixos.md)

---

## 0. 全体像

| 項目 | 内容 |
| --- | --- |
| 消えるもの | NVMe 上の Ubuntu、`/home/halby`、`/var/lib/docker`、`/etc` の設定 |
| 残るもの | `/mnt/data_ssd` 配下（syncthing 421G、misskey DB 12G、restic 231G+、gitea 等） |
| 引き継ぐもの | SSH ホスト鍵（sops の復号鍵を兼ねる）、sops の秘密、データディスク |
| 実行元 | 別ホスト (conoha など x86_64-linux) または NixOS インストーラ USB |
| 所要時間 | 事前 1〜2h / インストール 30〜60 分 / 検証 1h 程度 |

---

## 1. 事前チェックリスト

- [x] restic バックアップが完了している（2026-10-26 時点で 20 スナップショット）
- [x] `restic check` が通る（2026-10-26 実施）
- [ ] **復元テスト**: 別ディレクトリへ `restic restore latest --target /tmp/restore-test` して中身を確認
  （手順は [restore-test.md](./restore-test.md)。**2026-10-26 に Windows で実施済み**）
- [x] `secrets/minis/*` がすべて設定済み（samba / users / cloudflared / misskey / discord-bot）
  - `samba.yaml`（SMB パスワード）
  - `users.yaml`（halby の Unix パスワードハッシュ）
  - `cloudflared.yaml`（トンネルトークン）
  - `misskey-default.yml`（misskey 設定）
  - `discord-bot.yaml`（BOT_TOKEN）
- [x] `.sops.yaml` の `&minis` が**現在の minis のホスト鍵**から導出した値と一致（2026-10-26 確認）
- [x] `hardware.nix` を実機の情報で更新（2026-10-26 実施、§5）
- [x] 実行元ホストが用意できている（conoha、2026-10-26）
- [x] **`/home` の退避**（2026-10-26 実施、11G、§2）— 忘れるとデプロイ BOT の鍵・設定が消える

---

## 2. `/home` の退避（必須）

ルートディスクは消えるので、必要なものはデータディスクへ退避する。

```sh
sudo mkdir -p /mnt/data_ssd/migration-backup
sudo rsync -a --info=progress2 \
  --exclude '.cache' --exclude '.npm' --exclude '.bun' \
  --exclude 'node_modules' --exclude '.pnpm-store' \
  /home/halby/ /mnt/data_ssd/migration-backup/home/
```

> 2026-10-26 に実施済み（11G）。`.ssh` / `ci/tomarigi_hp_svelte`（`.env`, `.ssh`）/ `servers/misskey/.config` の存在を確認済み。

特に重要なもの:

| パス | 理由 |
| --- | --- |
| `~/.ssh` | 個人の鍵（ホスト鍵は `/etc/ssh` 側で別途引き継ぐ） |
| `~/ci/tomarigi_hp_svelte` | デプロイ BOT の作業コピー。`.ssh/`（デプロイ鍵）と `packages/*/.env*` を含む |
| `~/servers/*/.env*` | switchbot / magic_packet などの設定値（移行後に使うものだけ） |
| `~/.config` | 各種設定（chezmoi 管理外のもの） |
| `~/repos` | 個人リポジトリ（必要なら） |

> `~/ci` は 5.6G あるが、`node_modules` を除けば小さくなる。`.git` は残してよい。

---

## 3. サービスの停止（kexec 前に必須）

Postgres / Syncthing をきれいに止めてから電源を切る（データディスクの整合性のため）。

```sh
# misskey (db/redis/es/cloudflared を含む)
cd ~/servers/misskey && docker compose down

# syncthing / portainer / bot / magic packet
docker stop syncthing portainer-portainer-1 magic-packet-server 2>/dev/null
cd ~/ci/tomarigi_hp_svelte && docker compose down

# samba / tailscale は止めなくてよいが、smbd は止めておくと安全
sudo systemctl stop smbd nmbd

# 念のため同期
sync
```

> `docker compose down` で misskey の DB が正常終了していれば、次回起動時のリカバリは不要。

---

## 4. 実行元ホストの準備

`nixos-anywhere` は**対象機の外**から実行する（kexec で対象を再起動するため）。

### 第一候補: halby-desktop（NixOS 26.05 VM）

`halby-desktop.local:2422` の NixOS 26.05 (x86_64, 24 cores / 31GB / 949G free)。
カーネルが新しいので**ローカルビルドできる**。2026-10-30 にセットアップ済み。

```sh
# リポジトリ同期（秘密を含むので取り扱い注意）
rsync -a -e "ssh -p 2422 -i ~/.ssh/minis.pub -o IdentitiesOnly=yes" \
  --exclude .git --exclude '*.qcow2' --exclude result ./ halby-desktop.local:minis/

# 事前ビルド（インストールを速くする。任意）
ssh -p 2422 -i ~/.ssh/minis.pub halby@halby-desktop.local \
  'cd ~/minis && nix build .#nixosConfigurations.minis.config.system.build.toplevel'
```

halby-desktop から minis へは `halby@192.168.2.130`（LAN）で入れる（鍵は設定済み）。

### 代替: conoha

Ubuntu 20.04 / kernel 5.4 のため **NixOS 26.05 の closure をローカルビルドできない**
（`systemd-hwdb` が `Failed to determine if ... points to the root directory` で失敗）。
評価は通るので、`nixos-anywhere` に **`--build-on remote`** を付けて kexec 後の
インストーラ環境でビルドさせる。2026-10-25 に Nix 導入・`~/minis` 同期済み。

### 対象機への接続

どちらのホストも **halby ユーザー + sudo** で minis に入れる
（nixos-anywhere が sudo を検出して昇格する）。

## 5. ハードウェア定義の更新

`hosts/minis/hardware.nix` は暫定値。実機の値で置き換える。

方法 A: NixOS インストーラ上で採取（推奨）

```sh
nixos-generate-config --no-filesystems --root /tmp
# /tmp/etc/nixos/hardware-configuration.nix の kernel modules 等を hardware.nix へ転記
```

方法 B: `nixos-facter`（nixos-anywhere の `--generate-hardware-config` でも可）

```sh
nixos-facter > hardware.json
```

> 2026-10-26 に実機上で `nixos-generate-config --no-filesystems --root /tmp/hwgen` を実行し、
> `hosts/minis/hardware.nix` に反映済み（kernel modules: xhci_pci, ahci, nvme / kvm-intel）。

> `fileSystems` は disko が持つので**取り込まない**（`--no-filesystems`）。

---

## 6. インストール実行

```sh
# halby-desktop（推奨・ローカルビルド）
ssh -p 2422 -i ~/.ssh/minis.pub halby@halby-desktop.local
cd ~/minis
nix run github:nix-community/nixos-anywhere -- \
  --flake .#minis \
  --copy-host-keys \
  halby@192.168.2.130
```

conoha から実行する場合のみ `--build-on remote` を付ける（§4 の制約）。

- `--build-on remote` は conoha からの実行時のみ（カーネルが古くローカルビルド不可）。
  halby-desktop からはローカルビルドされる。
- `--copy-host-keys` は**必須**。sops の age identity（`/etc/ssh/ssh_host_ed25519_key`）を
  引き継がないと、起動後にすべての秘密が復号できなくなる。
- disko が NVMe を再パーティション（ESP 1G / swap 8G / root 残り）し、`/mnt/data_ssd` には触らない。
- 途中で kexec → インストーラ起動 → インストール → 再起動、と進む。

### インストーラ USB で行う場合

```sh
# インストーラ上で
git clone <このリポジトリ> /tmp/minis && cd /tmp/minis   # または USB に入れておく
nix --extra-experimental-features 'nix-command flakes' run \
  github:nix-community/disko -- --mode destroy,format,mount --flake .#minis
nixos-install --flake .#minis --root /mnt --no-root-password
# ホスト鍵を引き継ぐ
cp -a /etc/ssh/ssh_host_* /mnt/etc/ssh/   # 既存の Ubuntu から退避したもの
```

---

## 7. 初回起動チェック

```sh
ssh halby@minis

# 基本
hostname; nixos-version
sudo systemctl --failed
sudo ls /run/secrets/          # samba_halby, halby_password などが並ぶ

# ストレージ
findmnt /mnt/data_ssd
swapon --show                  # 8G
lsblk                          # vda1 ESP / vda2 swap / vda3 root

# 各サービス
systemctl is-active samba-smbd samba-nmbd cockpit.socket syncthing magic-packet-bridge
sudo pdbedit -L                # halby がいる
curl -sk -o /dev/null -w '%{http_code}\n' https://127.0.0.1:9090/
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8384/
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"mac":"FFFFFFFFFFFF"}' http://127.0.0.1:10840/

# misskey (イメージ pull に数分かかる)
systemctl status misskey
docker compose -f /etc/misskey/compose.yml ps
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3002/

# tailscale (初回は認証が必要)
sudo tailscale up            # ブラウザ認証、または --auth-key
tailscale status
```

### Syncthing のフォルダパス修正（重要）

旧環境はコンテナ内 `/var/syncthing` だったため、`config.xml` のフォルダパスが
`/var/syncthing/...` や `~/Assets` のままになっている。ネイティブでは
`/mnt/data_ssd/syncthing/...` に直す必要がある。

```sh
sudo systemctl stop syncthing
sudo sed -i 's#/var/syncthing#/mnt/data_ssd/syncthing#g' /mnt/data_ssd/syncthing/config/config.xml
sudo systemctl start syncthing
# GUI (8384) で各フォルダのパスと同期状態を確認
```

---

## 8. デプロイ BOT の復元

```sh
# チェックアウト（鍵は退避した ~/.ssh とリポジトリ内 .ssh を使う）
git clone git@github.com:TomarigiTei/tomarigi_hp_svelte.git ~/ci/tomarigi_hp_svelte
cd ~/ci/tomarigi_hp_svelte
pnpm install --frozen-lockfile

# .env / .ssh を退避データから戻す
rsync -a /mnt/data_ssd/migration-backup/home/ci/tomarigi_hp_svelte/ ~/ci/tomarigi_hp_svelte/ \
  --exclude node_modules --exclude .git

sudo systemctl restart discord-bot
journalctl -u discord-bot -f      # "Logged in as ..." を確認
```

---

## 9. 動作確認（サービス単位）

| サービス | 確認方法 |
| --- | --- |
| Samba | Mac の Finder から `smb://minis/halby` に接続 |
| Cockpit | `https://minis:9090` に halby + sops のパスワードでログイン、podman プラグインが見える |
| Syncthing | `http://minis:8384`、デバイス ID が旧環境と同じか |
| misskey | `https://misskey.halby24.com` が表示される（cloudflared 経由） |
| magic packet | 外部から `POST http://minis:10840/ {"mac": "..."}` で PC が起動する |
| restic | Windows から `restic snapshots` が見える（uid 1001 のまま） |
| Discord BOT | Discord でメンション + `ping` / `help` |

---

## 10. ロールバック

ルートディスクは退避していないため、**元の Ubuntu には戻せない**。障害時は:

1. NixOS インストーラ USB で起動し、`disko` + `nixos-install` を再実行
2. データディスクはそのまま残っているので、`/mnt/data_ssd` をマウントして確認
3. Windows の restic バックアップから `/home` 等を復元

事前に **NixOS インストーラ USB を 1 本用意しておく**こと。

---

## 11. 既知の注意点

- **ホスト鍵**: 引き継がないと sops が復号できない。引き継げなかった場合は
  新ホスト鍵を `ssh-to-age` で変換して `.sops.yaml` に追加し、`sops updatekeys` を実行。
  - 復号可否の確認は **`ssh-to-age -private-key -i <鍵>`** で得た identity を使う。
    sops-nix は内部で `ssh-to-age` ライブラリを使うため、これが実際の経路。
    `age -d -i /etc/ssh/ssh_host_ed25519_key` は native な age recipient に対しては
    失敗する（age CLI の SSH 対応の仕様）ので、この結果で判断しない。
  - 2026-10-26 に「`ssh-to-age < host key.pub` の recipient」と
    「`ssh-to-age -private-key -i host key` の identity」で復号できることを実機で確認済み。
- **SSH の host key 警告**: ホスト鍵を引き継ぐので、クライアント側の known_hosts はそのまま使える。
- **Tailscale**: `tailscale up` は手動。ホスト名は `networking.hostName = "minis"` で維持。
- **Cloudflare Tunnel**: token は sops 済み。DNS は変更不要。
- **misskey**: DB は `/mnt/data_ssd/misskey/db` をそのまま使う。初回起動でイメージ pull が走る。
  バージョンは 2025.4.0 固定（アップグレードは別作業）。
- **restic**: `restic` ユーザーの uid/gid は 1001 固定。リポジトリの所有者と一致させること。
- **sops の鍵バックアップ**: この Mac の `~/.config/sops/age/keys.txt` は 1Password 等に保管。
- **Nix の自動更新**: `nix.gc` は weekly。`system.autoUpgrade` は未設定（必要なら追加）。

---

## 付録: 事前クリーンアップ実施記録 (2026-10-26)

移行前の Ubuntu 上で実施した整理。データディスクは 816G 空き。

| 対象 | 結果 |
| --- | --- |
| Docker build cache | 58.97GB 削除 |
| 未使用イメージ | 46.3GB 削除（39 → 11、すべて稼働中） |
| 停止コンテナ | 2 個削除 |
| 未使用ネットワーク | 2 個削除 |
| tgt (iSCSI) | 停止 + 無効化 |
| vsftpd | 停止 + 無効化（廃止決定） |
| gitea | リポジトリを bundle 退避（`migration-backup/gitea-bundles/`、complete history 検証済み）→ スタック停止・データ 896M 削除 |
| /mnt/data_ssd/storage | `storage-2026-10-26.tar.zst`（3.5G）にアーカイブして削除（9.9G 解放、zstd 整合性確認済み） |
| restic の `*-restic-temp-*` | 14 個（154.6MB）削除 |

ルートディスクは 131G → 70G（61G 解放）。

退避物: `/mnt/data_ssd/migration-backup/`
- `gitea-bundles/`（2 リポジトリ、complete history）
- `storage-2026-10-26.tar.zst`（旧 storage 全体、9.9G → 3.5G）

---

## 付録: 実施記録 (2026-10-31)

- 実行元: halby-desktop（NixOS 26.05 VM）から `nixos-anywhere --copy-host-keys`
- 途中、kexec 後の DHCP で IP が `192.168.2.130` → `192.168.2.197` に変わり、
  一度目は接続先不一致で停止。インストーラを特定して `root@192.168.2.197` に対して再実行
- インストール完了・再起動。ホスト鍵は引き継がれ（`SHA256:uVHIF6...`）、sops 復号 OK
- 事後修正:
  - misskey の `default.yml` はコンテナ（非 root）から読めるよう `mode = "0444"`
  - cloudflared の ingress が `http://web:3002` のため `/etc/hosts` に `127.0.0.1 web`
  - Syncthing のフォルダパスを `/mnt/data_ssd/syncthing/...` に修正
  - デプロイ BOT を退避データから復元し `pnpm install` → ログイン確認
- 確認: misskey 公開 200 / samba / cockpit 200 / syncthing 200 / BOT ログイン /
  failed unit なし
- 残: `tailscale up`（認証待ち）
