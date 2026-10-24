# NixOS 構成 (WIP)

Ubuntu 素朴運用から NixOS + flake に移行するための最小構成。
現状の棚卸しは [current-state.md](./current-state.md) を参照。

## ファイル構成

```
flake.nix                 # nixosConfigurations: minis (実機) / minis-vm (確認用)
modules/common.nix        # 実機・VM 共通の最小設定
modules/server.nix        # firewall / tailscale / podman / journald
modules/samba.nix         # Samba の共有とパスワード投入
modules/secrets.nix       # sops-nix (age) の設定
hosts/minis/default.nix   # 実機のホスト設定
hosts/minis/hardware.nix  # 暫定。実機で nixos-generate-config したものに差し替える
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

- **firewall**: 有効化。現行 minis の待ち受けポートを明示許可 (21, 22, 139, 445, 2226, 3002, 3260, 8000, 8384, 9000, 10840, 18789-18790, 22000/tcp・udp, 137-138/udp)。`tailscale0` と `podman0`/`podman1` は trusted。
- **tailscale**: `services.tailscale.enable` のみ。認証 (`tailscale up`) は手動で行う。
- **podman**: rootless 既定 + `dockerCompat` (docker CLI シム) + `dockerSocket.enable` (`/run/docker.sock` → podman ソケット)。`halby` を `podman` グループに追加（root 相当の権限を持つ点に注意）。`docker-compose` (v5.4.0) も導入。
- **journald**: `SystemMaxUse=2G`, `SystemMaxFileSize=200M`。

VM で確認済み (2026-10-24):

- `firewall.service` active、iptables に許可ポートが入る
- `tailscaled` active（未ログイン状態）
- `podman info` が rootless で動作、`/etc/subuid` は自動採番
- `/run/docker.sock` 経由で `docker ps` / `docker run` / `docker-compose up` が動作（nginx を起動して HTTP 200 を確認）

portainer は `/run/docker.sock` をマウントすれば動く見込み（未検証）。
compose を podman ネイティブにするなら quadlet への移行を別途検討する。

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

### 実機インストール時の注意

- ホスト鍵を引き継がないと復号できない。`nixos-anywhere` でホスト鍵をコピーするか、
  インストール後に新しい公開鍵を `ssh-to-age` で変換して `.sops.yaml` に追加し、
  `sops updatekeys secrets/minis/samba.yaml` を実行する。
- `secrets/minis/samba.yaml` の `halby` は現在 `CHANGE_ME`。デプロイ前に実際の SMB パスワードへ変更すること
  (未設定のままだと `samba-password.service` が失敗する)。

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

## 実機投入 (未実施)

前提: 事前にバックアップ（現状 restic は 6 月から停止しているので注意）。

```sh
# 対象機でハードウェア定義を採取し、hosts/minis/hardware.nix を置き換える
nixos-generate-config --root /mnt

# インストール（既定ではディスクを消す）
nixos-anywhere --flake .#minis root@192.168.2.130
```

注意点:

- `hosts/minis/hardware.nix` の UUID は**現行 Ubuntu のパーティションを流用する前提**。`/` を再フォーマットするなら UUID が変わるので、生成し直すか disko で宣言的にパーティションを切る。
- `/mnt/data_ssd` (1.8T btrfs) は別ディスクなので、NVMe 側だけ入れ替えればデータは残せる。
- stateVersion は 26.05 固定（移行後に上げない）。
