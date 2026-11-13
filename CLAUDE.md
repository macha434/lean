# lean

## 言語

このリポジトリで作業するときの文章(コミットメッセージ、ドキュメント、
Issue/PRの説明、エージェントの報告文など)は日本語で書く。コード識別子・
JSON のキー名・ファイル内の固定文字列(フックが出力する `permissionDecisionReason`
など、利用者側の環境が日本語とは限らない箇所)は英語のままでよい。

README は `README.md` 1本のみ、日本語で書く。英語版は用意しない。

## バージョン

プラグインのバージョンは `plugins/lean/.claude-plugin/plugin.json` の
`version` だけで管理する。`.claude-plugin/marketplace.json` のエントリには
`version` を書かない(両方に書くと `plugin.json` が優先され、食い違いが
警告になるため)。利用者に更新が届くのは `version` が変わったときだけなので、
リリースのたびに必ず上げる。
