# サーバー管理用 (minis / conoha)

## 概要

自宅サーバーの MINIS (`ssh minis`) と ConoHa VPS の conoha (`ssh conoha`) を
宣言的に管理する。

## 移行状況

**2026-10-31 に NixOS 26.05 へ移行済み**。設定はこのリポジトリが正本。

- 反映: リポジトリを minis に同期して `sudo nixos-rebuild switch --flake ~/minis#minis`
  （または halby-desktop から `nixos-rebuild switch --target-host`）
- 旧 Ubuntu 時代の棚卸しは `docs/current-state.md`（履歴として保持）

## 現状の棚卸し

`docs/current-state.md` に 2026-10-24 時点の minis の実構成（ハード、ネットワーク、Docker サービス、データ配置、バックアップ、移行論点）を記録している。作業前に一読すること。

## よく使うコマンド

```sh
# 反映 (minis 上)
sudo nixos-rebuild switch --flake ~/minis#minis

# web (tomarigi_hp_svelte) のビルド環境。ツール一式は lib/build-tools.nix が正本
cd ~/minis && nix develop                 # node / pnpm / php+ast / composer / rsync / ssh
cd ~/minis && nix run .#web -- build-dev  # チェックアウトに入って pnpm script を実行
```

- 秘密情報は必ず sops (`secrets/`)。平文の鍵やトークンをチェックアウトに置かない。
  編集は `sops secrets/minis/<name>.yaml` (この Mac の age 鍵 `~/.config/sops/age/keys.txt` を使う)。
- `~/minis` はこのリポジトリの同期コピー。`.git` は含めない (`rsync -a --exclude='.git/'`)。
  ローカルの `~/repos/server/minis` を編集 → rsync → rebuild。

## ドキュメント

- `docs/nixos.md` — flake 構成、モジュール、VM での確認方法
- `docs/deploy.md` — 実機投入（Ubuntu → NixOS）の手順書・チェックリスト・ロールバック
- `docs/conoha-migration.md` — ConoHa VPS (conoha) の棚卸しと NixOS 移行手順
- `docs/restore-test.md` — restic の復元テスト手順と offsite コピーの注意

## アーキテクチャ

- NixOS 26.05 (flake) / disko / sops-nix
- Podman（docker-compose 互換ソケット経由）
- データディスク `/mnt/data_ssd`（btrfs、disko 対象外）

## テスト環境

MINISデプロイ前に仮想マシンなどで動作試験する