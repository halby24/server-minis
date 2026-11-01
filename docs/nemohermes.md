# NemoHermes (NVIDIA NemoClaw)

minis 上で NVIDIA NemoClaw の Hermes エージェント（`nemohermes`）を常駐させるための記録。
2026-11-01 時点で **CLI までの導入が完了し、サンドボックスは未作成**（推論プロバイダ未決定）。

- 本体は upstream の installer がユーザー単位で入れる。NixOS 側は前提だけを宣言する。
- NixOS は NemoClaw の検証対象外（Ubuntu 24.04 が主対象）。以下のつまずきは NixOS 固有。

## 構成

| 場所 | 中身 |
| --- | --- |
| `~/.local/bin/` | `nemohermes` / `nemoclaw` / `nemo-deepagents` の shim、`openshell`、`openshell-gateway` |
| `~/.npm-global/` | CLI の npm link 先（`nemohermes` = `nemoclaw` の alias） |
| `~/.nemoclaw/source/` | installer が clone した NemoClaw のソース（ビルド済み `dist/` を含む） |
| `~/.config/systemd/user/nemoclaw-openshell-gateway.service` | OpenShell gateway（onboarding で enable される） |
| `~/.zshrc` | installer が `~/.local/bin` の PATH 設定を追記する |
| サンドボックス | rootless Podman（`NEMOCLAW_GATEWAY_RUNTIME=podman`） |

ポートは dashboard `18789`、OpenAI 互換 API `8642`。どちらも **loopback バインド**なので
firewall は開けない。外から見るなら `ssh -L 18789:127.0.0.1:18789 minis`。

## NixOS 側の前提 (`modules/nemohermes.nix`)

```nix
environment.systemPackages = [ nodejs_22 binutils lsof ];  # installer の preflight 用
users.users.halby.linger = true;                            # systemd --user を常駐させる
system.activationScripts.binbash.text = "ln -sfn ${pkgs.bashInteractive}/bin/bash /bin/bash";
environment.sessionVariables.NEMOCLAW_GATEWAY_PORT = "8080";
programs.nix-ld.enable = true;                              # npm 製 ELF (prek 等) 用
```

それぞれの理由:

1. **Node.js は nvm ではなく nixpkgs。** installer は Node が無いと nvm で入れるが、
   nvm の Node は汎用 Linux 向け glibc バイナリで NixOS では動かない。`nodejs_22`
   (22.23.4 / npm 10.9.9) を入れておけば installer は nvm をスキップする。
   `strings` (binutils) と `lsof` は preflight が PATH 上で要求する。
2. **`/bin/bash` を足す。** `bin/nemoclaw.js` が gateway port の解決に
   `spawnSync("/bin/bash", …)` をハードコードしている。NixOS の `/bin` には `sh` しか無い。
3. **`NEMOCLAW_GATEWAY_PORT=8080` を固定する。** 未設定だと CLI は
   `PATH=/usr/bin:/bin` で自分の resolver を呼ぶが、NixOS の `/usr/bin` には
   `dirname` すら無いため必ず失敗し
   `Could not safely resolve the automatically selected NemoClaw gateway port` で落ちる。
   8080 は自動選択時の既定値と同じ。8080 が埋まったら 8990–9005 の自動選択は使えないので、
   そのときは別ポートを明示する。
4. **nix-ld。** `npm link` が走らせる `prek` などは汎用 Linux 向け動的リンク ELF。
   無効だと `NixOS cannot run dynamically linked executables` で失敗する（リンク自体は
   通ることもあるが、その後のツールが動かない）。
5. **linger。** onboarding が enable する `nemoclaw-openshell-gateway.service` を
   ログアウト後・再起動後も動かすため。

## インストール（実行済み）

同意が必要なので、対話で notice を確認したうえで非対話実行した。

```sh
export NEMOCLAW_AGENT=hermes \
       NEMOCLAW_GATEWAY_RUNTIME=podman \
       NEMOCLAW_DEFER_ONBOARDING=1 \
       NEMOCLAW_PROVIDER=build \
       NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1 \
       NEMOCLAW_DISABLE_TELEMETRY=1 \
       NEMOCLAW_GATEWAY_PORT=8080
curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash
```

- `--defer-onboarding` は「推論プロバイダ未決定のまま CLI だけ入れる」指定。
  サンドボックスもプロバイダも作られない。この指定は NVIDIA ホスト推論
  (`build` / `cloud` / `routed`) のときだけ許されるので `NEMOCLAW_PROVIDER=build` を添える
  （値は記録されない）。
- テレメトリは既定で NVIDIA の TEST 受信先へ送られる。`NEMOCLAW_DISABLE_TELEMETRY=1` で無効化。
- 結果: `nemohermes v0.0.140` / `openshell 0.0.116`。installer のログは
  `~/nemoclaw-install-*.log`。

## 次の手順（サンドボックス作成）

プロバイダを決めてから、minis 上で:

```sh
export PATH="$HOME/.local/bin:$PATH"
NEMOCLAW_GATEWAY_RUNTIME=podman nemohermes onboard
```

- 既定サンドボックス名は `hermes`。OpenClaw と並べるときは別名にする。
- サンドボックスイメージは約 2.4GB（展開時はもう少し）。`/` の空きは 400GB 以上ある。
- rootless Podman の前提は満たしている（`/run/user/1000/podman/podman.sock` 0660、
  cgroups v2、netavark + DNS、subuid/subgid 設定済み）。`NEMOCLAW_GATEWAY_RUNTIME=podman`
  を付け忘れると Docker を入れに行く（NixOS では失敗する）。
- onboarding 後に確認するもの:

```sh
nemohermes list
nemohermes hermes status
nemohermes hermes doctor
ssh -L 18789:127.0.0.1:18789 minis   # dashboard
```

## 運用

```sh
nemohermes status                 # 全体（sandbox 一覧 + host サービス）
nemohermes hermes logs --follow
nemohermes hermes recover         # 再起動後に forward が死んだとき
nemohermes hermes dashboard-url
```

アンインストールは `nemohermes uninstall`（Portable Ollama 等の後始末込み）。
`~/.nemoclaw` と `~/.local/bin` の shim は手で消す。

## 注意点

- **rsync で `.git` ファイルを運ばない。** `vps/minis/target` をそのまま送ると
  submodule の `.git`（`gitdir: ../../.git/modules/vps/minis`）までコピーされ、
  `nixos-rebuild --flake ~/minis#minis` が
  `failed to resolve path '/home/halby/minis/../../.git/modules/vps/minis'` で落ちる。
  `rsync -a --exclude='.git' ./ minis:minis/` のように **ディレクトリだけでなくファイルも**
  除外する。
- installer を再実行すると `~/.nemoclaw/source` を作り直す。CLI のバージョンは
  upstream の `lkg` タグに追従する。
- `nemohermes` は `~/.local/bin` にしか無い。非対話シェルでは PATH に入らないので、
  自動化では絶対パスか `export PATH="$HOME/.local/bin:$PATH"` を使う。
- 起動時の `ExperimentalWarning: SQLite is an experimental feature` は Node 22 の
  警告で、動作に影響しない。
