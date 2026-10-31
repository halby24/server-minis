# MINIS Server 管理用

## 概要

自宅サーバーのMINIS (`ssh minis`)　を宣言的に管理する

## 移行状況

**2026-10-31 に NixOS 26.05 へ移行済み**。設定はこのリポジトリが正本。

- 反映: リポジトリを minis に同期して `sudo nixos-rebuild switch --flake ~/minis#minis`
  （または halby-desktop から `nixos-rebuild switch --target-host`）
- 旧 Ubuntu 時代の棚卸しは `docs/current-state.md`（履歴として保持）

## 現状の棚卸し

`docs/current-state.md` に 2026-10-24 時点の minis の実構成（ハード、ネットワーク、Docker サービス、データ配置、バックアップ、移行論点）を記録している。作業前に一読すること。

## ドキュメント

- `docs/nixos.md` — flake 構成、モジュール、VM での確認方法
- `docs/deploy.md` — 実機投入（Ubuntu → NixOS）の手順書・チェックリスト・ロールバック
- `docs/restore-test.md` — restic の復元テスト手順と offsite コピーの注意

## アーキテクチャ

- NixOS 26.05 (flake) / disko / sops-nix
- Podman（docker-compose 互換ソケット経由）
- データディスク `/mnt/data_ssd`（btrfs、disko 対象外）

## テスト環境

MINISデプロイ前に仮想マシンなどで動作試験する