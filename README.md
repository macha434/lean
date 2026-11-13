# lean

大きなファイルの読み込み、定型コードの生成、冗長なテスト出力、肥大化した
CLAUDE.md — メインの会話のコンテキストを圧迫するものをまとめて逃がす
Claude Code プラグインである。

## 概要

- 対象ユーザー: 大きなファイルの読み込み・機械的なコード生成・テスト出力・
  CLAUDE.md の肥大化がトークン消費の大半を占めている Claude Code ユーザー
- 解決する課題: メインの会話に一度載った内容(2,000行のファイル、10,000行の
  テストログ、300行のCLAUDE.md)は、セッションが終わるまでコンテキストに
  残り続け、以降のすべてのターンで課金対象になる
- 価値: 大きなファイルと機械的なコード生成は Haiku のサブエージェントへ、
  テスト出力はその場でのフィルタリングへ、CLAUDE.md の肥大化は書き込み前の
  警告・ブロックへ。会話に届くのは必要な情報だけになる

これは Spotify が Claude Code のトークン使用量を約 90% 削減した手法を、単一ベンダー
で再構成したものである。Spotify の `shunt` は社内基盤 Portal を経由して Gemini Flash
に処理を振り分けるが、本プラグインは Claude Haiku だけで同じことを行うため、通常の
Claude Code さえあれば誰でも利用できる。

## 主な機能

- **大きなファイル読み込みのブロック**: メインの会話における大きなファイルの
  全体読み込みをブロックし、委譲するよう Claude に指示する
- **テスト出力のフィルタリング**: `npm test`・`pytest`・`go test` などの
  テストランナー実行を検知し、失敗箇所(`FAIL`/`ERROR`)だけに絞って返す。
  Windows の PowerShell ツールにも対応している
- **CLAUDE.md 肥大化のガード**: `CLAUDE.md` への書き込みが閾値を超えそうな
  場合、書き込み前に警告し、さらに超える場合はブロックして skills への
  移動を促す
- **`bulk-reader`**: 使い捨てのコンテキストでファイルを読み、質問に対する
  抜粋だけを返す Haiku のサブエージェント
- **`code-writer`**: 設計の決まった機械的なコードをディスクへ直接書き込み、
  パスだけを報告する Haiku のサブエージェント。生成されたコードは会話に
  一切入らない
- **常にフェイルオープン**: `jq` がない、パスが読めない、フックの入力が壊れて
  いる — いずれの失敗経路でも元の操作を許可する。コスト最適化がセッションを
  止める原因になってはならない

## 仕組み

フックとエージェントの2層構成である。

| 層 | ファイル | 役割 |
|---|---|---|
| フック | `hooks/check-file-size.sh` | `Read` を横取りし、閾値を超える全体読み込みをブロックする |
| フック | `hooks/filter-bash-test-output.sh` | `Bash` を横取りし、テストランナーの出力を失敗箇所だけに絞る |
| フック | `hooks/filter-powershell-test-output.sh` | `PowerShell` を横取りし、テストランナーの出力を失敗箇所だけに絞る |
| フック | `hooks/check-claude-md-length.sh` | `Edit`/`Write` を横取りし、`CLAUDE.md` の肥大化を書き込み前に警告・ブロックする |
| エージェント | `agents/*.md` | `model: haiku` で実作業を担当する |

`check-file-size.sh` は次のいずれかに該当する場合、必ず読み込みを許可する。

- サブエージェント内で実行されている(`agent_id` が存在する)場合。委譲先自身は
  常に自由に読めるため、ループにならない
- `offset` または `limit` で範囲が限定されている場合。狙いを絞った読み込みは
  そもそも推奨される形である
- ファイルがバイナリ、存在しない、読み取り不可、または行数が閾値未満の場合

`filter-bash-test-output.sh` はテストランナーと認識できるコマンドだけを
書き換える。既に `grep` を含む、または `>` でリダイレクトしているコマンドは
二重フィルタを避けるためそのまま通す。

`filter-powershell-test-output.sh` は同じ一覧のテストコマンドを PowerShell
ツール向けに書き換える。

```
<元のコマンド> | Out-String -Stream | Select-String -Pattern 'FAIL|ERROR|error:' -Context 0,5 | Select-Object -First <上限行数>
```

既に `Select-String`(エイリアス `sls` を含む)・`Out-File`・`Tee-Object` を
含む、または `>` でリダイレクトしているコマンドは、二重フィルタを避けるため
そのまま通す。いずれもサブエージェント内では何もしない。

`2>&1` は付けない。Windows PowerShell 5.1 ではネイティブコマンドへの `2>&1` が
各行を `ErrorRecord` に包み、終了コードが 0 でも `$?` を false にするためである。

`check-claude-md-length.sh` は `PostToolUse` では書き込みをブロックできない
(exit code 2 が効かない)ため、`PreToolUse` の時点で編集後の行数を予測して
判定する。`Write` はそのまま内容の行数、`Edit` は現在の行数 +
(`new_string` の行数 − `old_string` の行数) で見積もる。厳密ではないが
警告としては十分な精度である。

## 必要なもの

- プラグインに対応した Claude Code
- `jq` — ない場合フックはすべてを許可し、プラグインは何もしない

## セットアップ

```bash
claude plugin marketplace add macha434/lean
claude plugin install lean@macha434-plugins
```

## 使い方

呼び出す操作は不要である。インストール後、対象の操作をしようとすると
自動的にフックが働く。

大きなファイルを読もうとすると:

```
lean: src/app/routes.ts is 1,240 lines (threshold 350).
Reading it in full would load all of it into this conversation's context.

Delegate it instead: call the Task/Agent tool with subagent_type "bulk-reader"...
```

`CLAUDE.md` が閾値に近づくと:

```
lean: CLAUDE.md is about to reach 260 lines (warn threshold 250, block at 300).
Consider moving some of this into a skill before it hits the block threshold.
```

任意のタイミングで明示的に委譲することもできる。

> bulk-reader エージェントを使って、`src/http/` のどこでリトライポリシーが
> 設定されているか調べて。

> code-writer エージェントを使って、`parseDuration` のテーブル駆動テストを
> 追加して。

## 設定

いずれもフック実行時に環境変数から読み込まれる。

| 変数 | 既定値 | 効果 |
|---|---|---|
| `LEAN_MIN_LINES` | `350` | この行数以上の全体読み込みをブロックする。数値以外を指定した場合は既定値に戻る |
| `LEAN_BASH_MAX_LINES` | `100` | Bash 用テスト出力フィルタの `head` に渡す最大行数。PowerShell 用の既定値も兼ねる |
| `LEAN_PS_MAX_LINES` | 未設定 | PowerShell 用テスト出力フィルタの `Select-Object -First` に渡す最大行数。未設定なら `LEAN_BASH_MAX_LINES`、それも未設定なら `100`。数値以外は `100` に戻る |
| `LEAN_CLAUDE_MD_WARN_LINES` | `250` | この行数以上になる編集で警告する(許可はする) |
| `LEAN_CLAUDE_MD_BLOCK_LINES` | `300` | この行数以上になる編集をブロックする |
| `LEAN_DISABLE` | 未設定 | `1` を設定すると全フックを無効化する |

## 注意

- **終了コードが見えなくなる**: テスト出力フィルタは、元のコマンドの出力を
  パイプで絞る。そのため、書き換え後のコマンドの終了コードは元のテスト
  コマンドのものではなく、パイプ末尾のコマンド(Bash は `head`、PowerShell は
  `Select-Object`)のものになる。PowerShell でも `$LASTEXITCODE` は元の
  テストコマンドの結果を反映するとは限らない。テストの成否は出力に
  `FAIL`/`ERROR` が現れるかで判断する。終了コードが必要な場合は、
  Claude Code を起動する環境で `LEAN_DISABLE=1` を設定してフックを無効にする
- **絞り込みは行単位**: 失敗を示す行にパターンが含まれないランナーでは、失敗が
  出力から落ちることがある

## 開発

```bash
tests/run-tests.sh
```

記録済みの `PreToolUse` ペイロードで各フックスクリプトを駆動し、フェイルオープン
の経路を含めて各ケースの許可/ブロックを検証する。

## FAQ

**Q. 委譲先のサブエージェントまでブロックされないか?**
A. されない。`agent_id` はサブエージェント内でのみフックのペイロードに現れ、
存在する場合フックは常に元の操作を許可する。

**Q. メインの会話でどうしても生のテキストが必要な場合は?**
A. `offset`/`limit` を付けて読み直せばよい。範囲指定の読み込みはブロックされない。
フック全体を止めたい場合は `LEAN_DISABLE=1` を設定する。

**Q. `code-writer` もフックで強制されるのか?**
A. されない。「この生成は機械的である」ことを確実に判定する手段がないため、
こちら側は強制ではなくエージェントの説明による方針として提供している。

**Q. CLAUDE.md のブロックを一度だけ回避したい**
A. その1回のコマンドに `LEAN_DISABLE=1` を付けて実行する。

## クレジット

フックとエージェントによる委譲、ファイルサイズ閾値のアイデアは
[spotify/portal-ai-plugins](https://github.com/spotify/portal-ai-plugins)
に由来する。

## ライセンス

MIT
