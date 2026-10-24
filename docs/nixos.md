# NixOS 構成 (WIP)

Ubuntu 素朴運用から NixOS + flake に移行するための最小構成。
現状の棚卸しは [current-state.md](./current-state.md) を参照。

## ファイル構成

```
flake.nix                 # nixosConfigurations: minis (実機) / minis-vm (確認用)
modules/common.nix        # 実機・VM 共通の最小設定
hosts/minis/default.nix   # 実機のホスト設定
hosts/minis/hardware.nix  # 暫定。実機で nixos-generate-config したものに差し替える
hosts/vm/default.nix      # VM テスト用 (qemu-vm, KVM, SSH 2222 転送)
keys/halby.pub            # halby の SSH 公開鍵 (GitHub の halby24.keys と同一)
```

方針:

- 共通部分は `modules/` に切り出し、実機と VM の両方から import する（VM で事前検証するため）。
- 秘密情報はまだ扱っていない。必要になったら sops-nix / agenix を検討する。

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
