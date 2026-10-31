> **履歴**: これは 2026-10-24 時点（Ubuntu 時代）の棚卸し。2026-10-31 に NixOS へ移行済み。
> 現在の構成は `docs/nixos.md` とリポジトリの設定を参照。

# minis 現状構成メモ (2026-10-24 時点)

`ssh minis` で実機に入って棚卸しした結果。NixOS 化を検討する前のスナップショット。
数値・バージョンは取得時点のもの。

## 1. ハードウェア

| 項目 | 内容 |
| --- | --- |
| 筐体 | AZW MINI S (Beelink Mini S 系) / Intel N100 (4C4T, VT-x) |
| BIOS | ADLNV104 (2023-02-06) |
| RAM | 15 GiB (4.0G used / 10G cache) + swap 4G (`/swap.img`) |
| OS ディスク | NVMe 476.9G `/dev/nvme0n1p2` ext4 → `/` (122G used, 28%) |
| データディスク | SATA SSD 1.8T `/dev/sda1` **btrfs** → `/mnt/data_ssd` (679G used, 37%) |
| モニタ | HDMI 接続あり (GNOME デスクトップとして稼働) |

- btrfs-progs 未インストール (`btrfs` コマンド無し) / smartmontools 未インストール。
- `/mnt/data_ssd` は fstab で `/dev/disk/by-uuid` 指定。

## 2. OS / 基本設定

- Ubuntu 24.04.5 LTS (noble), kernel `7.0.0-38-generic` (HWE), `linux-generic-hwe-24.04`
- 最終起動 2026-10-21 21:49 (uptime 2日)
- Ubuntu **Desktop** 版 (gdm3 + GNOME セッションが seat0 で稼働中)
- ユーザ: `halby` (uid 1000, zsh, パスワードレス sudo), `restic` (uid 1001, bash, system 用)
- ホスト名 `minis`, `/etc/hosts` は Docker Desktop 追記あり
- unattended-upgrades 有効 (自動更新)
- **ufw は inactive** (ホスト側 FW なし)
- 自作 systemd unit は無し (全部パッケージ由来 or snap)
- Docker Desktop も入っているが未使用 (`docker context` は moby の `default`)

### ネットワーク

| IF | アドレス | 備考 |
| --- | --- | --- |
| enp1s0 | 192.168.2.130/24 | 有線。デフォルトルート (metric 100) |
| wlo1 | 192.168.2.129/24 | Wi-Fi。同じセグメントで **両方 UP**、デフォルトルートも保持 (metric 600) |
| tailscale0 | 100.80.53.13 | tailnet `minis` |

- IPv6 グローバル (2404:7a82:...) が両 IF に付与、一時アドレスも複数。
- Docker bridge が 172.17–172.24 に点在 (`docker0` と 5 本ブリッジ)。
- 有線・無線が同一 L2 に二重接続されている状態 (mDNS/avahi, samba の名前解決で紛らわしい)。

### アクセス経路

| 経路 | 内容 |
| --- | --- |
| SSH | port 22。`sshd_config.d` で `KbdInteractiveAuthentication no` 以外はほぼデフォルト |
| Tailscale | `minis` = 100.80.53.13。`tailscale serve` で `https://minis.tail54a7c.ts.net/` → `localhost:18789` (openclaw gateway, tailnet only) |
| Cloudflare Tunnel | misskey の compose 内 `cloudflared` → `https://misskey.halby24.com/` を公開 |
| RDP | 3389 で `gnome-remote-desktop` が LISTEN (grdctl status は disabled/認証情報未設定と表示) |
| SMB | 139/445 |
| FTP | 21 (vsftpd, `ssl_enable=NO` = 平文) |

## 3. 稼働サービス (Docker)

Docker CE 5:29.8.2 (`/var/lib/docker`, overlay2, json-file)。compose プロジェクト:

| compose | 場所 | 内容 | 公開ポート |
| --- | --- | --- | --- |
| misskey | `~/servers/misskey` | Misskey 2025.4.0 + Postgres15 + Redis7 + ES6.4.2-oss + cloudflared | 3002 |
| gitea | `~/servers/gitea` | Gitea 1.19.0 + Postgres14 | 8000 (HTTP), 2226 (SSH) |
| syncthing | `~/servers/syncthing` | syncthing (host network) | 8384, 22000 |
| openclaw | `~/servers/openclaw/openclaw` | `openclaw:local` (ローカルビルド) gateway | 18789, 18790 |
| portainer | `~/servers/portainer` | Portainer CE | 9000 |
| magic_packet_bridge | `~/servers/magic_packet_bridge` | ts-node 常駐 (`node .../ts-node src/main.ts`, pid 3858) | 10840 |
| tomarigi_hp_svelte | `~/ci/tomarigi_hp_svelte` | Discord bot + log cleaner (24h 前に起動) | - |

- `~/servers/switchbot_data` の compose は**現在停止中** (SwitchBot データロガー、`db/` は空)。
- ゴミコンテナ: `ecstatic_kirch` (8ヶ月前 Exited), `hopeful_carson` (hello-world) → 未削除。
- Docker 使用量: images 59.4GB (reclaimable 38.5GB), build cache 59GB (reclaimable 10GB), volumes 3 個。
- `docker-compose.yml` 内に **秘密情報が平文** (misskey の `TUNNEL_TOKEN`, ES パスワード, gitea の DB パスワード等)。openclaw は `.env` に API キー群。

### ホスト側サービス (systemd, running)

`docker`, `tailscaled`, `smbd`/`nmbd`, `vsftpd`, `tgt` (iSCSI, 3260 LISTEN だが **ターゲット 0 件**), `gdm3` + `gnome-remote-desktop`,
`avahi-daemon`, `cups`/`cups-browsed`, `bluetooth`, `ModemManager`, `snapd`, `unattended-upgrades`, `chrony` ではなく `systemd-timesyncd`。

- `qemu-kvm.service` は enabled だが libvirt/VM は無し (実体なし)。
- chrome-remote-desktop / parsec を apt で導入済み (cron.daily に chrome-remote-desktop)。

## 4. データ配置

`/mnt/data_ssd` (btrfs) 配下が実データ置き場。ホーム側はシンボリックリンク:

| パス | サイズ | 内容 |
| --- | --- | --- |
| `/mnt/data_ssd/syncthing` | 421G | syncthing データ (`~/servers/syncthing/syncthing` → symlink) |
| `/mnt/data_ssd/restic` | 231G | restic リポジトリ (owner `restic`, 最終更新 2026-06-18 で**停止**) |
| `/mnt/data_ssd/misskey` | 12G | misskey の db/files (`~/servers/misskey/{db,files}` → symlink) |
| `/mnt/data_ssd/storage` | 9.9G | 旧データ `repos/` (C103Draft 等 8 個), `shares/` (halby, homes, public, timemachine, windows_backup) |
| `/mnt/data_ssd/gitea` | 896M | gitea data/postgres (`~/servers/gitea/{data,postgres}` → symlink) |

- `~/ci` 5.6G, `~/repos` 392M (asm_helloworld, react-reference-viewer), `~/servers/openclaw` 326M。
- syncthing フォルダ: Default (`/var/syncthing/Sync`), Assets (`~/Assets`), ArtStock, Works。

## 5. サービスの中身

- **Misskey**: `misskey.halby24.com`。ローカルユーザ 5、ノート ~2,850、連合キャッシュ `user` 100,623 行 (ほぼリモート)。
  DB/Redis/ES の認証情報は compose の example 値のまま (`example-misskey-user` / `example-misskey-pass`)。
  ES は 6.4.2 とかなり古い。
- **Gitea**: `minis:8000`。ユーザ 1、リポジトリ 2 (`dairichan_unity_project.git`, `fbxtransformconverter.git`)。1.19.0 で古い。
- **OpenClaw**: 生成 AI ゲートウェイ。tailscale serve の公開先。`.env` に各種 API キー。
- **Portainer**: 9000。`/var/run/docker.sock` をマウント。
- **magic_packet_bridge**: host network で 10840。他ホストの WoL 用。
- **Samba**: 共有 `[halby]` = `/home/halby` (書き込み可), `[syncthing]` = `/mnt/data_ssd/syncthing` (valid users=halby)。ユーザは halby のみ。
- **vsftpd**: ローカルユーザ認証, 平文, 匿名不可。

## 6. バックアップ

- restic リポジトリが `/mnt/data_ssd/restic` (231G) にある。`restic` ユーザの authorized_keys は GitHub の `halby24.keys` から取得 → **他マシンから SFTP で push する構成**と推測。
- ただし snapshot は 2026-06-07 / 06-18 の 2 つだけで、**約4ヶ月更新が止まっている**。
- リポジトリは**同じ物理ディスク上**。offsite コピーは未確認。
- ホスト自体の設定バックアップ・IaC は無し (本リポジトリが唯一の記録)。

## 7. 管理 (dotfiles)

- minis 上も `chezmoi` 管理 (`~/.local/share/chezmoi`, origin `github.com/halby24/dotfiles`)。
- `.zshrc` / `.zshenv` / `.zprofile` は chezmoi 管理下。
- `chezmoi status` で `.Brewfile`, `.agents`, `.claude`, `.codex` など多数が `M` (ドリフトあり。ディレクトリ権限差分の可能性大)。

## 8. 移行 (NixOS 化) に向けた論点メモ

1. **デスクトップ前提をどうするか**: GNOME + gdm + RDP + Chrome Remote Desktop + Parsec が入っている。サーバ用途に絞るならごっそり捨てられる (RAM/更新ノイズも減る)。モニタは HDMI 接続中。
2. **Docker を Podman に置き換えるか**: misskey (5 コンテナ) / gitea / syncthing / portainer / openclaw / CI bot の compose 群が対象。Portainer は Docker socket 前提なので Podman 移行時に要検討。
3. **秘密情報の整理**: compose 直書きのトークン・パスワード・example 認証情報を sops/agenix 等に寄せたい。openclaw の `.env` も同様。
4. **データ移行**: `/mnt/data_ssd` は btrfs 単体 (冗長性なし)。移行時に 421G syncthing + 231G restic + 12G misskey をどう運ぶか。
5. **バックアップ停止の解消**: restic が 6 月から止まっている。移行の前に/後に再開するかを決める。
6. **不要物の棚卸し**: tgt (iSCSI, ターゲット0), qemu-kvm, vsftpd (平文), cups/bluetooth/ModemManager, Docker Desktop, 旧 `/mnt/data_ssd/storage`, 停止中の switchbot logger, ゴミコンテナ 2 個, build cache 59GB。
7. **ネットワーク整理**: 有線/無線の二重接続、ufw 無効、`tailscale serve` で openclaw を tailnet 公開している点。
8. **misskey の公開経路**: cloudflared トンネル (compose 内) が本番。NixOS 側でも同等のトンネル設定が必要。
9. **バージョン陳腐化**: gitea 1.19.0 / misskey ES 6.4.2 / Ubuntu 24.04 のまま。移行と同時に上げるかは要判断。
10. **監視・ログ**: json-file ログのみ。journald も既定。NixOS 化で journald 設定・ローテーションを入れる余地あり。

## 9. 既知の不調 (軽微)

- `snap.firmware-updater.firmware-notifier.service` が 3 時間おきに失敗ログを吐く。
- `pam_lastlog.so` が存在せず、ログイン時に PAM 警告 (`ubuntu-desktop-minimal` の欠落)。
- `grdctl status` は RDP 証明書が invalid / credentials 未設定と表示 (ポートは開いている)。

## 10. 未確認 / 要ヒアリング

- Cloudflare トンネルのホスト名設定はダッシュボード側 (リポジトリに設定ファイル無し)。
- restic を push しているのはどのマシンか、暗号化パスワードの保管場所。
- `~/ci/tomarigi_hp_svelte` が CI からどうデプロイされているか。
- openclaw / magic_packet_bridge を NixOS 移行後も残すか。
- Tailscale ACL / 外部公開ポリシーの方針。
