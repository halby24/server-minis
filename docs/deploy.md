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

- [ ] restic バックアップが完了している（`restic snapshots` で最新が見える）
- [ ] `restic check` が通る
- [ ] **復元テスト**: 別ディレクトリへ `restic restore latest --target /tmp/restore-test` して中身を確認
  （手順は [restore-test.md](./restore-test.md)。**2026-10-26 に Windows で実施済み**）
- [ ] `secrets/minis/*` がすべて設定済み
  - `samba.yaml`（SMB パスワード）
  - `users.yaml`（halby の Unix パスワードハッシュ）
  - `cloudflared.yaml`（トンネルトークン）
  - `misskey-default.yml`（misskey 設定）
  - `discord-bot.yaml`（BOT_TOKEN）
- [ ] `.sops.yaml` の `&minis` が**現在の minis のホスト鍵**から導出した値と一致
- [ ] `hardware.nix` を実機の情報で更新（手順は §5）
- [ ] 実行元ホストが用意できている（§4）
- [ ] **`/home` の退避**（§2）— これを忘れるとデプロイ BOT の鍵・設定が消える

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

## 4. 実行元ホストの準備（conoha の例）

`nixos-anywhere` は**対象機の外**から実行する（kexec で対象を再起動するため）。

```sh
# conoha に Nix を入れる（初回のみ）
ssh conoha 'sh <(curl -L https://nixos.org/nix/install) --daemon'
ssh conoha 'mkdir -p ~/.config/nix && echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf'

# リポジトリを同期（秘密を含むので取り扱い注意）
rsync -a --exclude .git --exclude '*.qcow2' --exclude result \
  ./ conoha:~/minis/
```

> 2026-10-25 時点で conoha は Nix 導入済み・`~/minis` 同期済み。

対象機へは **halby ユーザー + sudo** で入れる（nixos-anywhere が sudo を検出して昇格する）。

```sh
ssh conoha 'cd ~/minis && nix run github:nix-community/nixos-anywhere -- --help'
```

### conoha の制約（重要）

conoha は Ubuntu 20.04 / kernel 5.4 で、**NixOS 26.05 の closure をローカルビルドできない**
（`systemd-hwdb` が `Failed to determine if ... points to the root directory` で失敗する）。

- `nix eval`（評価）は成功するので、`nixos-anywhere` の `--eval-store auto` は使える
- ビルドは **kexec 後のインストーラ環境（minis, kernel 6.18 / RAM 15G）に任せる** = `--build-on remote`
- どうしても conoha でビルドしたい場合は、より新しいカーネルのホストに替える

---

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

> `fileSystems` は disko が持つので**取り込まない**（`--no-filesystems`）。

---

## 6. インストール実行

```sh
ssh conoha
cd ~/minis

nix run github:nix-community/nixos-anywhere -- \
  --flake .#minis \
  --build-on remote \
  --copy-host-keys \
  halby@192.168.2.130
```

- `--build-on remote` は conoha のカーネルが古いため必須（§4）。ビルドは kexec 後の
  インストーラ環境で行われる。
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
- **SSH の host key 警告**: ホスト鍵を引き継ぐので、クライアント側の known_hosts はそのまま使える。
- **Tailscale**: `tailscale up` は手動。ホスト名は `networking.hostName = "minis"` で維持。
- **Cloudflare Tunnel**: token は sops 済み。DNS は変更不要。
- **misskey**: DB は `/mnt/data_ssd/misskey/db` をそのまま使う。初回起動でイメージ pull が走る。
  バージョンは 2025.4.0 固定（アップグレードは別作業）。
- **restic**: `restic` ユーザーの uid/gid は 1001 固定。リポジトリの所有者と一致させること。
- **sops の鍵バックアップ**: この Mac の `~/.config/sops/age/keys.txt` は 1Password 等に保管。
- **Nix の自動更新**: `nix.gc` は weekly。`system.autoUpgrade` は未設定（必要なら追加）。
