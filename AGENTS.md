# サーバー管理用 (minis / conoha)

## 概要

自宅サーバーの MINIS (`ssh minis`) と ConoHa VPS の conoha (`ssh conoha`) を
NixOS + flake で宣言的に管理する。このリポジトリが設定の正本。

`my-all-servers` の `vps/minis` はこのリポジトリの submodule（同じもの）。

## 反映

```sh
# minis 上（~/minis は .git を除いた同期コピー）
sudo nixos-rebuild switch --flake ~/minis#minis

# または halby-desktop などから
nixos-rebuild switch --target-host ... --flake .#minis
```

編集は手元のチェックアウトで行い、minis へ同期してから rebuild する:

```sh
rsync -a --exclude='.git/' ./ minis:minis/
```

## よく使うコマンド

```sh
# web (tomarigi_hp_svelte) のビルド環境。ツール一式は lib/build-tools.nix が正本
cd ~/minis && nix develop                 # node / pnpm / php+ast / composer / rsync / ssh
cd ~/minis && nix run .#web -- build-dev  # チェックアウトに入って pnpm script を実行

nix flake check
```

- 秘密情報は必ず sops (`secrets/`)。平文の鍵やトークンをチェックアウトに置かない。
  編集は `sops secrets/minis/<name>.yaml`（この Mac の age 鍵 `~/.config/sops/age/keys.txt`）。

## ドキュメント

- `docs/nixos.md` — 構成、モジュール、ビルド環境、ディスク、sops、VM 確認、再インストール
- `docs/nemohermes.md` — NVIDIA NemoClaw (nemohermes) の導入と NixOS 固有の注意点
- `docs/restore-test.md` — restic の復元テスト手順と offsite コピーの注意
- conoha の OS 再インストール: `my-all-servers` の `vps/conoha/docs/install.md`

## アーキテクチャ

- NixOS 26.05 (flake) / disko / sops-nix
- Podman（docker-compose 互換ソケット経由）
- データディスク `/mnt/data_ssd`（btrfs、disko 対象外）
- デプロイ前に VM (`minis-vm` / `minis-test`) で動作確認する
