# MINIS Server 管理用

## 概要

自宅サーバーのMINIS (`ssh minis`)　を宣言的に管理する

## 移行

移行前の段階ではUbuntuで素朴に管理されているため、宣言的管理に移行したい

## 現状の棚卸し

`docs/current-state.md` に 2026-10-24 時点の minis の実構成（ハード、ネットワーク、Docker サービス、データ配置、バックアップ、移行論点）を記録している。作業前に一読すること。

## ドキュメント

- `docs/nixos.md` — flake 構成、モジュール、VM での確認方法
- `docs/deploy.md` — 実機投入（Ubuntu → NixOS）の手順書・チェックリスト・ロールバック
- `docs/restore-test.md` — restic の復元テスト手順と offsite コピーの注意

## アーキテクチャ

随時追加

- NixOS
- Podman

## テスト環境

MINISデプロイ前に仮想マシンなどで動作試験する