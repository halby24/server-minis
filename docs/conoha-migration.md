# conoha (ConoHa VPS) の棚卸しと NixOS 移行

2026-11-01 に Ubuntu 20.04 から NixOS 26.05 へ移行した。設定の正本は `hosts/conoha/`。
このドキュメントは実際の手順と、ハマった点の記録。

## 1. 旧構成 (Ubuntu 20.04.6 / kernel 5.4)

| 項目 | 内容 |
| --- | --- |
| ホスト | ConoHa VPS 3.0 `Bridge-VPS`（`160.251.180.206` / `2400:8500:2002:3167:160:251:180:206`） |
| Tailscale | `conoha` = `100.86.106.81` |
| スペック | Intel Xeon (Icelake) 1 vCPU / RAM 461MiB / swap 2G |
| ディスク | `/dev/vda` 30G（BIOS boot 3M + ext4 `/`） |
| ブート | BIOS (GRUB)。EFI パーティション無し |
| ネットワーク | eth0: **IPv4 は静的**（`160.251.180.206/23`, GW `160.251.180.1`）、IPv6 も静的。**DHCP は無い** |

### 稼働サービス

| サービス | 実体 | ポート |
| --- | --- | --- |
| Caddy 2.11.4 | `/etc/caddy/caddy.json` | 80, 443, 8443, 8888 |
| MediaMTX 1.11.3 | systemd (ユーザー halby) | 8554/tcp, 8000-8001/udp, 1935/tcp, 18080/tcp, 8889/tcp, 8189/udp, 8890/tcp |
| Mailpit | Docker `axllent/mailpit:latest` | 8025/tcp, 587→1025/tcp |
| Tailscale | `tailscaled` | 41641/udp |
| fail2ban | sshd jail | - |
| ufw | 22, 25, 80, 443, 554, 8554, 8000-8001/udp, 8888, 8443, 1935(tailscale0), 587(219.94.129.236 と tailnet) | - |

### 移行対象のデータ

| データ | 旧場所 | 新場所 |
| --- | --- | --- |
| Mailpit DB | `/home/halby/servers/mailpit/mailpit/mailpit.db` (108K) | `/var/lib/mailpit/mailpit.db` |
| Tailscale state | `/var/lib/tailscale/` (92K) | `/var/lib/tailscale/` |
| SSH ホスト鍵 | `/etc/ssh/ssh_host_*` | `/etc/ssh/`（`nixos-install` 前に復元） |
| Caddy 設定 | `/etc/caddy/*` | `hosts/conoha/caddy.nix` |
| Cloudflare token | `/etc/caddy/caddy_token.env` | `secrets/conoha/cloudflare.yaml` |
| Mailpit SMTP AUTH | compose の環境変数 | `secrets/conoha/mailpit.yaml` |
| halby パスワード | `/etc/shadow` | `secrets/conoha/users.yaml` |

Caddy の証明書は移行せず、NixOS 側の `security.acme` で再取得した。

## 2. なぜ nixos-anywhere ではなく ISO か

nixos-anywhere は kexec に **RAM 1.5GB 以上**（swap 除く）を要求する。
この VPS は 512MB プランで、前払いプランのため API からのプラン変更も不可
（コントロールパネルでも上位プランへ変更できないことを確認済み）。

そのため、**ConoHa の ISO レスキューモード**で NixOS インストーラ ISO を起動し、
`nixos-install --system` でインストールした。

## 3. インストーラ ISO

`hosts/conoha-installer/` が ISO の定義。対象システムの closure を ISO の Nix store に
焼き込むので、インストール時にネットワークからのダウンロード・評価が不要。

```sh
nix build .#nixosConfigurations.conoha-installer.config.system.build.isoImage
# → result/iso/nixos-*.iso（約 1.8GB）
```

ISO には `conoha-install` スクリプトが入っている。やること:

1. `/dev/vda` を GPT で再作成（3M bios_grub + ext4 root）
2. 2G の一時 swap を作成
3. `nixos-install --root /mnt --system <closure> --no-root-password`
4. `/root/conoha-data` があれば SSH ホスト鍵と Tailscale state を復元

### アップロードとレスキュー起動

ISO は Image API に直接 PUT する（**1.8GB を `-T` でストリーム送信**。
`--data-binary` はメモリ不足になる）。作成時に
`hw_rescue_bus=ide`, `hw_rescue_device=cdrom` を指定する。

```sh
# 1) イメージ作成
curl -X POST -H "X-Auth-Token: $TOKEN" -H 'Content-Type: application/json' \
  -d '{"name":"conoha-nixos-installer","disk_format":"iso","hw_rescue_bus":"ide","hw_rescue_device":"cdrom","container_format":"bare"}' \
  https://image-service.c3j1.conoha.io/v2/images
# 2) アップロード
curl -X PUT -H "X-Auth-Token: $TOKEN" -H 'Content-Type: application/octet-stream' \
  -T nixos-*.iso https://image-service.c3j1.conoha.io/v2/images/$IMG/file
# 3) レスキューモードで起動
curl -X POST -H "X-Auth-Token: $TOKEN" -H 'Content-Type: application/json' \
  -d '{"rescue":{"rescue_image_ref":"'$IMG'"}}' \
  https://compute.c3j1.conoha.io/v2.1/servers/$SID/action
```

### レスキュー環境のネットワーク

**ConoHa は DHCP を提供しない。** ISO 起動後は ens3 に IP が無いので、
既知の静的 IP を手で設定する（NetworkManager が邪魔をするので止める）。

```sh
sudo systemctl stop NetworkManager
sudo ip addr add 160.251.180.206/23 dev ens3
sudo ip route add 160.251.180.0/23 dev ens3
sudo ip route add default via 160.251.180.1
```

これで `ssh root@160.251.180.206` が通る（ISO の root 鍵は `keys/halby.pub` と `keys/air.pub`）。

## 4. インストール手順（実施済み）

```sh
# Mac から退避データを ISO 環境へ
ssh root@160.251.180.206 'mkdir -p /root/conoha-data/tailscale /root/conoha-data/mailpit'
scp ~/conoha-backup-*/ssh/ssh_host_* root@160.251.180.206:/root/conoha-data/
scp -r ~/conoha-backup-*/tailscale/. root@160.251.180.206:/root/conoha-data/tailscale/
scp -r ~/conoha-backup-*/mailpit/. root@160.251.180.206:/root/conoha-data/mailpit/

# ISO 上でインストール（バックグラウンドでログを取る）
ssh root@160.251.180.206 'nohup conoha-install > /root/install.log 2>&1 &'
# INSTALL_OK を待つ

# レスキュー解除
curl -X POST ... -d '{"unrescue":null}' .../action
```

## 5. ハマった点（重要）

### 5.1 パーティションラベル

disko を使う設定では、インストール後の initrd が
`/dev/disk/by-partlabel/disk-main-root` を探す。手動パーティションで
`root` というラベルにすると **emergency mode** になる。

`conoha-install` は `sgdisk -c 2:disk-main-root`（と 1 は `disk-main-bios`）を付ける。
既にインストール済みでラベルが違う場合は `parted /dev/vda` の
`name 2 disk-main-root` で直せる。

### 5.2 systemd-networkd が有効にならない

`networking.useNetworkd = true` だけでは **サービスが enable されない**。
`systemd.network.enable = true` も必要。これが無いと IP が付かず SSH も上がらない。

```nix
networking.useNetworkd = true;
systemd.network.enable = true;
```

### 5.3 IPv4 は DHCP ではない

`networking.useDHCP` や `DHCP=ipv4` では IP が付かない。`hosts/conoha/default.nix` の
`systemd.network.networks."10-wan"` で静的アドレス・ゲートウェイを設定している。

### 5.4 swap の置き場所

`swapDevices` に `/var/swap/swapfile` を指定すると、初回起動時に
`/var/swap` が無くて `mkswap` が失敗する。`/swapfile` に置くこと。

### 5.5 Caddy の証明書

Caddy の plugin ビルドを避けるため、証明書は `security.acme`（lego, Cloudflare DNS-01）が
取得し、Caddy は `/var/lib/acme/media.halby24.com/{cert,key}.pem` を読む。
`security.acme.certs.<domain>.group = "caddy"` と `reloadServices = [ "caddy" ]` を設定。

## 6. 移行後の確認

```sh
ssh conoha 'systemctl --failed; swapon --show; tailscale status | head -1'
curl -I https://media.halby24.com/        # TLS と 404 (MediaMTX HLS) が返る
ssh conoha 'ss -ltn | grep -E ":(22|80|443|587|8554|8888|8443)"'
```

- Tailscale は state を復元したので IP は `100.86.106.81` のまま。
- SSH ホスト鍵も復元済み（フィンガープリント不変）なので sops が復号できる。
- Mailpit の DB は起動後に `/var/lib/mailpit/mailpit.db` へコピーし、
  `chown mailpit:mailpit` して `mailpit-default` を再起動する。

## 7. ロールバック

1. ConoHa コントロールパネルでブートボリュームをバックアップから復元
2. サーバーを起動
3. 必要なら退避した Tailscale state を戻す

## 8. 既知の注意点

- **RAM 512MB。** Nix のビルドを conoha 上で行うと OOM しやすい。ビルドは minis /
  halby-desktop で行い、closure を `nix copy` する。
- MediaMTX は 1.11 → 1.18 に上がった。設定は互換な範囲に整理済み。
- Caddy の証明書は NixOS 側で再取得。Cloudflare token に DNS:Edit 権限が必要。
- 公開 SSH (22) は開いている。fail2ban と鍵認証のみ。
- ConoHa の API プラン変更は前払いプランでは不可。ISO を使うこと。
