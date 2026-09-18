#!/bin/bash
# pre-push フックの回帰テスト。使い捨てのリポジトリを作り、pre-push の stdin 形式を
# 模して直接呼び出す。判定はフックの終了コード (0 = push 許可, 非0 = 中止)。
#
#   bash .githooks/pre-push.test.sh
#
# Docker が必要 (フックが secretlint のイメージを使う)。フックの実体は
# ~/.githooks/pre-push、つまりこのリポジトリへの symlink を検査する。
HOOK=~/.githooks/pre-push
Z=0000000000000000000000000000000000000000
LEAK='DSN=postgres://admin:RealProdPw@prod.example.com:5432/db'
RC='{"rules":[{"id":"@secretlint/secretlint-rule-preset-recommend","rules":[{"id":"@secretlint/secretlint-rule-database-connection-string","options":{"allows":["/^postgres:\\/\\/postgres:dummy@localhost\\/db$/"]}}]}]}'
pass=0; fail=0
D=$(mktemp -d)

newrepo() { rm -rf "$D/$1"; mkdir -p "$D/$1"; cd "$D/$1" || exit 1
  git init -q .; git config commit.gpgsign false; git config user.email t@t; git config user.name t; }

# hook <local_oid> <remote_oid> → OUT / RC を設定する
hook() { OUT=$(printf 'refs/heads/main %s refs/heads/main %s\n' "$1" "$2" | "$HOOK" origin url 2>&1); STATUS=$?; }

check() { # check <名前> <ok|block>
  if { [ "$2" = ok ] && [ "$STATUS" -eq 0 ]; } || { [ "$2" = block ] && [ "$STATUS" -ne 0 ]; }; then
    echo "  PASS  $1"; pass=$((pass+1)); return
  fi
  echo "  FAIL  $1 (exit=$STATUS)"; sed 's/^/          /' <<<"$OUT" | tail -3; fail=$((fail+1))
}

# base コミットを作り、その後の変更を1コミットにして検査させる
scenario() { newrepo "$1"; echo ok > a.txt; git add -A; git commit -qm base; BASE=$(git rev-parse HEAD); }
commit_and_hook() { git add -A; git commit -qm change; hook "$(git rev-parse HEAD)" "$BASE"; }

echo "--- 検出できること ---"
scenario s1; echo "$LEAK" > leak.env; commit_and_hook
check "秘密を含むファイル" block

scenario s2; echo "$LEAK" > secret.txt; echo secret.txt > .gitignore
git add -f secret.txt .gitignore; commit_and_hook
check ".gitignore で除外した追跡ファイル" block

scenario s3; echo "$LEAK" > leak.env; printf '**/*\n' > .secretlintignore; commit_and_hook
check ".secretlintignore で全除外" block

scenario s4; echo "$LEAK" > .secretlintrc.backup; commit_and_hook
check ".secretlintrc.backup に隠した秘密" block

newrepo s5; echo ok > a.txt; ln -s a.txt link; git add -A; git commit -qm base; BASE=$(git rev-parse HEAD)
rm link; echo "$LEAK" > link; commit_and_hook
check "symlink→通常ファイルの type change" block

scenario s6; printf '%s' "$LEAK" > "$(printf 'new\nline.env')"; commit_and_hook
check "改行を含むパス" block

scenario s7; mkdir -p 'dir with space'; echo "$LEAK" > 'dir with space/a b.env'; commit_and_hook
check "空白を含むパス" block

newrepo s8; echo "$LEAK" > leak.env; git add -A; git commit -qm root
hook "$(git rev-parse HEAD)" "$Z"
check "新規ブランチ (ルートコミット)" block

echo "--- 設定による回避を許さないこと ---"
scenario c1; echo "$LEAK" > leak.env; printf '%s\n' '{"secretlint":{"rules":[]}}' > package.json; commit_and_hook
check "package.json の secretlint フィールドで無効化" block

scenario c2; echo "$LEAK" > leak.env
printf 'process.stderr.write("JS_EXECUTED\\n");\nmodule.exports={rules:[]};\n' > .secretlintrc.json; commit_and_hook
if grep -q JS_EXECUTED <<<"$OUT"; then
  echo "  FAIL  .secretlintrc.json の中身が JavaScript (実行された)"; fail=$((fail+1))
else check ".secretlintrc.json の中身が JavaScript" block; fi

scenario c3; echo ok > b.txt; printf '%s\n' '{ broken json' > .secretlintrc.json; commit_and_hook
check "壊れた .secretlintrc.json" block

for degen in '' '{}' '{"rules":[]}' 'null' '[]' '{"rules":null}'; do
  scenario "c4$RANDOM"; echo "$LEAK" > leak.env
  printf '%s\n' '{"secretlint":{"rules":[]}}' > package.json
  printf '%s' "$degen" > .secretlintrc.json; commit_and_hook
  check "preset を含まない設定 [${degen:-空}]" block
done

scenario c5; echo ok > b.txt; printf '%s\n' "$RC" > .secretlintrc.yaml; printf '%s\n' '{"rules":[]}' > .secretlintrc.yml; commit_and_hook
check ".secretlintrc.yaml と .yml の同時存在" block

scenario c6; echo 'module.exports={}' > .secretlintrc.js; commit_and_hook
check ".secretlintrc.js" block

scenario c7; echo "$LEAK" > leak.env; git add -A; git commit -qm change
printf '%s\n' "$RC" > .secretlintrc.json   # 作業ツリーにだけ緩い設定を置く (コミットしない)
hook "$(git rev-parse HEAD)" "$BASE"
check "未コミットの設定による回避" block

newrepo c8; echo ok > a.txt; git add -A; git commit -qm base; BASE=$(git rev-parse HEAD)
git branch other
OUT=$(printf 'refs/heads/main %s refs/heads/main %s\nrefs/heads/other %s refs/heads/other %s\n' \
  "$(git rev-parse HEAD)" "$Z" "$(git rev-parse HEAD)" "$Z" | "$HOOK" origin url 2>&1); STATUS=$?
check "複数 ref の同時 push" block

echo "--- 正当な push を妨げないこと ---"
scenario o1; echo 'DSN=postgres://postgres:dummy@localhost/db' > app.env; printf '%s\n' "$RC" > .secretlintrc.json; commit_and_hook
check "リポジトリ設定で許可した DSN" ok

scenario o2; printf '%s\n' "$RC" > .secretlintrc.json; commit_and_hook
check "設定ファイルだけの push" ok

scenario o3; echo ok > b.txt; commit_and_hook
check "通常のファイル変更" ok

scenario o4; echo ok > 'weird*name.txt'; commit_and_hook
check "glob 文字を含むファイル名" ok

newrepo o5sub; echo hi > f.txt; git add -A; git commit -qm base
scenario o5; git -c protocol.file.allow=always submodule add -q "$D/o5sub" sub 2>/dev/null; commit_and_hook
check "submodule (gitlink) を含む push" ok

newrepo o6; echo ok > a.txt; git add -A; git commit -qm base
hook "$Z" "$(git rev-parse HEAD)"
check "ブランチ削除のみ" ok


echo "--- 組み込み ignore による回避を許さないこと ---"
scenario g1; mkdir -p node_modules/pkg; echo "$LEAK" > node_modules/pkg/index.js; commit_and_hook
check "node_modules 配下の秘密" block

scenario g2; mkdir -p nested; echo "$LEAK" > nested/.secretlintrc.json; commit_and_hook
check "ネストした .secretlintrc.json に隠した秘密" block

scenario g3; echo "$LEAK" > .secretlintignore.backup; commit_and_hook
check ".secretlintignore.backup に隠した秘密" block

scenario g4; mkdir -p nested; printf '%s\n' "$RC" > nested/.secretlintrc.yaml; commit_and_hook
check "ネストした .secretlintrc.yaml" block

scenario g5; mkdir -p 'nested/.secretlintrc.json'; echo "$LEAK" > 'nested/.secretlintrc.json/leak.env'
echo harmless > also-changed.txt; commit_and_hook
check ".secretlintrc.json という名前のディレクトリに隠した秘密" block

scenario g6; mkdir -p '.secretlintignore'; echo "$LEAK" > '.secretlintignore/leak.env'
echo harmless > also-changed.txt; commit_and_hook
check ".secretlintignore という名前のディレクトリに隠した秘密" block

scenario g7; mkdir -p 'node_modules/.bin'; echo "$LEAK" > 'node_modules/.bin/leak'
echo harmless > also-changed.txt; commit_and_hook
check "node_modules 配下 + 無害な変更の併用" block

scenario g8; printf 'nothing\n' > .secretlintignore; commit_and_hook
check ".secretlintignore の変更 (サポート外)" block

scenario g9; echo "$LEAK" > .secretlintignore; echo harmless > also-changed.txt; commit_and_hook
check ".secretlintignore 自体に隠した秘密" block

# git の index に大文字小文字だけ違う 2 パスを入れる (macOS の作業ツリーでは作れない)
scenario g10
blob_leak=$(printf '%s\n' "$LEAK" | git hash-object -w --stdin)
blob_ok=$(printf 'harmless\n' | git hash-object -w --stdin)
git update-index --add --cacheinfo "100644,$blob_leak,Leak.env"
git update-index --add --cacheinfo "100644,$blob_ok,leak.env"
git commit -qm change; hook "$(git rev-parse HEAD)" "$BASE"
check "大文字小文字だけ違う 2 パス (一時領域で衝突)" block

scenario g11; echo ok > b.txt
printf '{"rules":[{"id":"@secretlint/secretlint-rule-preset-recommend"}]}\0' > .secretlintrc.json
git add -A; git commit -qm change; hook "$(git rev-parse HEAD)" "$BASE"
check "NUL を含む .secretlintrc.json" block

echo "--- 設定だけの push でも JSON を検証すること ---"
scenario v1; printf '%s\n' '{"rules":[{"id":"@secretlint/secretlint-rule-preset-recommend"} broken' > .secretlintrc.json; commit_and_hook
check "設定だけの push で壊れた JSON" block

echo "--- 既知の制約 ---"
scenario k1; echo "$LEAK" > leak.env; git add -A; git commit -qm add
rm leak.env; git add -A; git commit -qm del; hook "$(git rev-parse HEAD)" "$BASE"
[ "$STATUS" -eq 0 ] && echo "  KNOWN 中間コミットにだけある秘密は検出されない" \
                || echo "  INFO  中間コミットにだけある秘密が検出された (exit=$STATUS)"

cd /; rm -rf "$D"
echo; echo "結果: $pass pass / $fail fail"
[ "$fail" -eq 0 ]
