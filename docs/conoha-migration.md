# conoha (ConoHa VPS) の棚卸しと NixOS 移行

2026-10-31 時点で稼働中の Ubuntu 20.04 を NixOS 26.05 に置き換えるための記録。
設定の正本は `hosts/conoha/`。

## 1. 現行構成 (Ubuntu 20.04.6 / kernel 5.4)

| 項目 | 内容 |
| --- | --- |
| ホスト | ConoHa VPS 3.0 `Bridge-VPS`（`160.251.180.206` / `2400:8500:2002:3167:160:251:180:206`） |
| Tailscale | `conoha` = `100.86.106.81` |
| スペック | Intel Xeon (Icelake) 1 vCPU / RAM 461MiB / swap 2G |
| ディスク | `/dev/vda` 30G（BIOS boot 3M + ext4 `/`） |
| ブート | BIOS (GRUB)。EFI パーティション無し |
| ネットワーク | eth0: IPv4 は DHCP（固定 IP が返る）、IPv6 は静的 + デフォルトルート |

### 稼働サービス

| サービス | 実体 | ポート |
| --- | --- | --- |
| Caddy 2.11.4 | `/usr/local/bin/caddy` + `/etc/caddy/caddy.json` | 80, 443, 8443, 8888 |
| MediaMTX 1.11.3 | `~/.local/bin/mediamtx` + `~/.config/mediamtx/mediamtx.yml` | 8554/tcp, 8000-8001/udp, 1935/tcp, 18080/tcp, 8889/tcp, 8189/udp, 8890/tcp |
| Mailpit | Docker `axllent/mailpit:latest` + compose | 8025/tcp, 587→1025/tcp |
| Tailscale | `tailscaled` | 41641/udp |
| fail2ban | sshd jail (maxretry 5 / bantime 24h) | - |
| ufw | 22, 25, 80, 443, 554, 8554, 8000-8001/udp, 8888, 8443, 1935(tailscale0), 587(219.94.129.236 と tailnet) | - |

- Caddy は `media.halby24.com` を `127.0.0.1:18080`（MediaMTX の HLS）へ reverse proxy。
  証明書は Cloudflare DNS-01（`/etc/caddy/caddy_token.env` の `CF_API_TOKEN`）。
- MediaMTX の認証は IP ベース。publish は Tailscale のみ、read は全世界、admin は localhost。
- Mailpit の SMTP は 587 で、Docker の `DOCKER-USER` チェーンで送信元を制限していた。
- Docker は Mailpit の 1 コンテナだけ（hello-world のゴミ 1 個あり）。

### 移行対象のデータ

| データ | 場所 | 移行 |
| --- | --- | --- |
| Mailpit DB | `/home/halby/servers/mailpit/mailpit/mailpit.db` (108K) | 新 `/var/lib/mailpit/mailpit.db` へコピー |
| Tailscale state | `/var/lib/tailscale/tailscaled.state` ほか (92K) | 新 `/var/lib/tailscale/` へコピー（IP 維持） |
| SSH ホスト鍵 | `/etc/ssh/ssh_host_*` | `nixos-anywhere --copy-host-keys` で引き継ぎ |
| Mediamtx 設定 | `~/.config/mediamtx/mediamtx.yml` | `hosts/conoha/mediamtx.yml` に反映済み（秘密なし） |
| Caddy 設定 | `/etc/caddy/{Caddyfile,caddy.json}` | `hosts/conoha/caddy.nix` に移植 |
| Cloudflare token | `/etc/caddy/caddy_token.env` | `secrets/conoha/cloudflare.yaml` |
| Mailpit SMTP AUTH | compose の環境変数 | `secrets/conoha/mailpit.yaml` |
| halby パスワード | `/etc/shadow` | `secrets/conoha/users.yaml` |

Caddy の証明書（`/var/lib/caddy`）は移行しない。NixOS 側で lego が再取得する。

## 2. NixOS 側の設計

| 旧 | 新 |
| --- | --- |
| Ubuntu + ufw | NixOS + nftables (`networking.firewall`) |
| Caddy 自前 DNS-01 (plugin) | `security.acme` (lego) + Caddy が証明書ファイルを読む |
| Docker Mailpit + iptables | `services.mailpit` + nftables |
| ntpd | systemd-timesyncd（NixOS 既定） |
| cloud-init / netplan | systemd-networkd（MAC で match、IPv4 DHCP + IPv6 静的） |
| swapfile 2G | `swapDevices` で 2G の swapfile |

- Caddy は plugin 入りビルドを避けるため、ACME を NixOS に任せる。
- Mailpit は `DynamicUser` を無効化し、静的ユーザー `mailpit` で `/var/lib/mailpit` を使う。
- MediaMTX は nixpkgs の 1.18.x に上がる（設定は互換な範囲に整理）。
- ファイアウォールは旧 ufw の許可ポートを踏襲。587 と 1935 は送信元で制限。

## 3. 移行手順

### 3.1 事前バックアップ

ConoHa コントロールパネルでブートボリュームのバックアップ（またはスナップショット）を取る。
これがロールバックの唯一の確実な手段。

作業マシン（minis など）にデータを退避する。

```sh
mkdir -p ~/conoha-backup
rsync -a --rsync-path="sudo rsync" conoha:/var/lib/tailscale/ ~/conoha-backup/tailscale/
rsync -a --rsync-path="sudo rsync" conoha:/home/halby/servers/mailpit/mailpit/ ~/conoha-backup/mailpit/
ssh conoha 'sudo tar -C /etc/ssh -cf - ssh_host_ed25519_key ssh_host_ed25519_key.pub' \
  | tar -C ~/conoha-backup -xf -
```

### 3.2 ビルド確認

```sh
cd ~/minis   # このリポジトリを同期したもの
nix build .#nixosConfigurations.conoha.config.system.build.toplevel
```

### 3.3 nixos-anywhere

対象機の外（minis か halby-desktop）から実行する。conoha は RAM が 512MB しかないので
`--build-on remote` は使わない（kexec 後のインストーラ上でビルドすると OOM しやすい）。

```sh
nix run github:nix-community/nixos-anywhere -- \
  --flake .#conoha \
  --copy-host-keys \
  halby@160.251.180.206
```

- `--copy-host-keys` は必須。SSH ホスト鍵 = sops の age identity。
- disko が `/dev/vda` を再パーティションする（3M bios_grub + ext4 root）。
- kexec が通らない場合は ConoHa の ISO マウントで NixOS インストーラを起動し、
  `disko --mode destroy,format,mount --flake .#conoha` → `nixos-install` に切り替える。

### 3.4 初回起動後のデータ戻し

```sh
ssh conoha

# Tailscale（IP 100.86.106.81 を維持する）
sudo systemctl stop tailscaled
sudo install -d -m 700 -o root -g root /var/lib/tailscale
sudo install -m 600 -o root -g root ~/tailscaled.state /var/lib/tailscale/tailscaled.state
sudo systemctl start tailscaled
tailscale status

# Mailpit（初回起動で /var/lib/mailpit が作られてから）
sudo systemctl stop mailpit-default
sudo install -m 600 -o mailpit -g mailpit mailpit.db /var/lib/mailpit/mailpit.db
sudo systemctl start mailpit-default
```

### 3.5 確認

```sh
# 証明書
sudo systemctl status 'acme-media.halby24.com.service'
curl -I https://media.halby24.com/

# MediaMTX
ss -tulpn | grep -E '8554|1935|8889|8890|18080'

# Mailpit (SMTP)
nix shell nixpkgs#swaks --command swaks --server 127.0.0.1:587 --auth tomarigi:<password> --to test@example.com

# fail2ban
sudo fail2ban-client status sshd
```

## 4. ロールバック

1. ConoHa コントロールパネルでブートボリュームをバックアップから復元
2. サーバーを起動
3. もし Tailscale の state を上書きしていれば、退避した `tailscaled.state` を戻す

## 5. 既知の注意点

- **RAM 512MB。** Nix のビルドを conoha 上で行うと OOM しやすい。ビルドは minis /
  halby-desktop で行い、conoha は `--build-on remote` のビルド先にしない。
- MediaMTX は 1.11 → 1.18 に上がる。設定は互換な範囲に整理したが、初回に
  `journalctl -u mediamtx` で警告を確認する。
- Caddy の証明書は再取得になる。Cloudflare token に DNS:Edit 権限が必要。
- `default` セキュリティグループの ingress は同一 SG 内のみ。公開ポートは
  `RTSP` SG の 554/8554/8888 と Caddy の 80/443/8443。
- 公開 SSH (22) は引き続き開く。fail2ban と鍵認証のみ。
- conoha のホスト名は `conoha`。Tailscale の ACL は IP `100.86.106.81` を前提にしているので、
  state を移して IP を維持する。
