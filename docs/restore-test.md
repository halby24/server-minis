# restic 復元テスト手順

バックアップは「戻せて初めてバックアップ」。実機移行の前に、リポジトリから実際に
ファイルを復元できることを確認する。

- リポジトリ: `sftp:restic@minis:/mnt/data_ssd/restic`
- 実行場所: **HALBY-DESKTOP (Windows)**（restic のパスワードがそこにあるため）
- リポジトリの中身: HALBY-DESKTOP のバックアップ（minis のデータではない）

---

## 1. スナップショットの確認

```powershell
$env:RESTIC_REPOSITORY = "sftp:restic@minis:/mnt/data_ssd/restic"
restic snapshots
```

- 最新のスナップショット ID と日時を控える
- パス（`Paths`）が期待どおりか確認

## 2. 整合性チェック

```powershell
restic check
```

構造と参照のチェック（数分）。次にデータの一部を実際に読むチェック:

```powershell
restic check --read-data-subset=5%
```

- 5% でも数分〜十数分かかることがある（231G 超のリポジトリ）
- 余裕があれば `--read-data-subset=10%` など

## 3. 統計の確認

```powershell
restic stats latest
```

ファイル数・合計サイズが想定どおりか。

## 4. 部分復元（まず小さく）

```powershell
restic ls latest | Select-Object -First 30     # パスを確認
restic restore latest --target D:\restic-restore-test --include "/C/Users/halby/Documents"
```

- いきなり全部復元しない（時間・容量）
- `--include` はスナップショット内のパス表記に合わせる（`restic ls` で確認）

## 5. 復元結果の検証

```powershell
Get-ChildItem D:\restic-restore-test -Recurse -File |
  Measure-Object -Property Length -Sum
```

- 元データのファイル数・合計サイズと比較
- いくつかファイルを開いて壊れていないか確認
- 可能ならハッシュ比較:

```powershell
Get-FileHash D:\restic-restore-test\...\somefile.txt
```

## 6. 後片付け

```powershell
Remove-Item -Recurse -Force D:\restic-restore-test
```

---

## 判定基準

- [x] `restic snapshots` で最新スナップショットが見える（2026-10-26 に 20 件を確認）
- [x] `restic check` が exit 0（2026-10-26 実施、エラーなし）
- [ ] `restic check --read-data-subset=5%` が exit 0
- [ ] 復元したファイルが開ける
- [ ] ファイル数・サイズ（またはハッシュ）が元と一致

### 実施記録

| 日付 | 内容 | 結果 |
| --- | --- | --- |
| 2026-10-26 | `restic check`（構造・参照） | エラーなし |
| 2026-10-26 | 中断アップロードの残骸 `*-restic-temp-*` が 14 個 | 参照されていない（check は通る）。`--read-data` 後に整理予定 |
| 未実施 | `restic check --read-data-subset=5%` | データ内容の実読チェック |
| 未実施 | 部分復元とハッシュ検証 | 実際に戻せるかの確認 |

## 失敗したとき

1. エラーメッセージを記録（`restic check` の出力）
2. `restic rebuild-index` を試す
3. 破損がある場合（restic 0.17+）:
   - `restic repair index`
   - `restic repair snapshots`
   - `restic repair packs`
4. 直近のスナップショットで同じ検証をやり直す

---

## 重要な注意

### リポジトリが同一ディスク上にある

`/mnt/data_ssd/restic` はバックアップ対象と同じ物理ディスク (SATA SSD) 上にある。
**ディスクが壊れるとバックアップも一緒に失う**。offsite コピーを作ること。

```powershell
# 例: 外付け HDD (D:) に複製
$env:RESTIC_PASSWORD2 = "<オフサイト側のパスワード>"
restic copy --repo2 D:\restic-offsite
```

（`restic init --repo2 ...` で複製先を初期化してから `restic copy`）

### minis のデータはこのリポジトリに含まれない

このリポジトリは Windows PC のバックアップ。minis 側の
`/mnt/data_ssd`（syncthing 421G、misskey DB 12G）は別途バックアップが必要。

移行時は disko が NVMe だけを消すのでデータディスクは残るが、
「消さない」ことと「バックアップがある」ことは別問題。余裕があれば
`/mnt/data_ssd` の重要部分（misskey DB / syncthing の設定）を
外付けディスクへコピーしておく。
