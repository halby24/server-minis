# restic 復元テスト手順

バックアップは「戻せて初めてバックアップ」。定期的にリポジトリから実際にファイルを
復元できることを確認する。

- リポジトリ: `sftp:restic@minis:/mnt/data_ssd/restic`
- 実行場所: **HALBY-DESKTOP (Windows)**（restic のパスワードがそこにあるため）
- このリポジトリの中身は **HALBY-DESKTOP のバックアップ**（minis のデータではない）

## 1. スナップショットの確認

```powershell
$env:RESTIC_REPOSITORY = "sftp:restic@minis:/mnt/data_ssd/restic"
restic snapshots
```

最新のスナップショット ID と日時、`Paths` が期待どおりかを確認する。

## 2. 整合性チェック

```powershell
restic check                    # 構造と参照（数分）
restic check --read-data-subset=5%   # データを実際に読む（231G 超なので数分〜十数分）
```

## 3. 統計の確認

```powershell
restic stats latest
```

ファイル数・合計サイズが想定どおりか。

## 4. 部分復元

いきなり全部復元しない（時間・容量）。

```powershell
restic ls latest | Select-Object -First 30     # パス表記の確認
restic restore latest --target D:\restic-restore-test --include "/C/Users/halby/Documents"
```

`--include` はスナップショット内のパス表記に合わせる。

## 5. 復元結果の検証

```powershell
Get-ChildItem D:\restic-restore-test -Recurse -File |
  Measure-Object -Property Length -Sum
Get-FileHash D:\restic-restore-test\...\somefile.txt
```

- 元データのファイル数・合計サイズと比較する
- いくつかファイルを開いて壊れていないか確認する
- ハッシュが取れるものは元と比較する

## 6. 後片付け

```powershell
Remove-Item -Recurse -Force D:\restic-restore-test
```

## 失敗したとき

1. エラーメッセージを記録（`restic check` の出力）
2. `restic rebuild-index` を試す
3. 破損がある場合（restic 0.17+）: `restic repair index` → `repair snapshots` → `repair packs`
4. 直近のスナップショットで同じ検証をやり直す

## 重要な注意

### リポジトリがバックアップ対象と同じディスク上にある

`/mnt/data_ssd/restic` はバックアップ対象と同じ物理ディスク (SATA SSD) 上にある。
**ディスクが壊れるとバックアップも一緒に失う。** offsite コピーを作ること。

```powershell
restic init --repo2 D:\restic-offsite          # 初回のみ
$env:RESTIC_PASSWORD2 = "<オフサイト側のパスワード>"
restic copy --repo2 D:\restic-offsite
```

### minis のデータはこのリポジトリに含まれない

このリポジトリは Windows PC のバックアップ。minis 側の `/mnt/data_ssd`
（syncthing・misskey DB など）は別途バックアップが必要。

再インストールで disko が消すのは NVMe だけでデータディスクは残るが、
「消さない」ことと「バックアップがある」ことは別問題。重要部分（misskey DB /
syncthing の設定）は外付けディスクへコピーしておく。
