#!/usr/bin/env bun
/**
 * guard-remote — Claude Code の PreToolUse フック。Bash コマンドのうち git push と ssh 系の接続を止める
 *
 * permissions.deny はコマンド先頭の前方一致なので、`git -C dir push` やパイプ・サブシェル・`bash -c`
 * の中に置かれたものを止められない。ここではシェルの字句を読んで単純コマンドごとに判定する。
 * 止めたときは exit 2 で理由を Claude に返す。
 */

// ---------------------------------------------------------------------------
// コントラクト
// ---------------------------------------------------------------------------

/** PreToolUse フックが stdin で受け取る入力のうち、使う部分 */
type HookInput = { tool_input?: { command?: unknown } };

/** 演算子で区切られた単純コマンド 1 つ分の語の並び */
type SimpleCommand = string[];

// ---------------------------------------------------------------------------
// 字句解析
// ---------------------------------------------------------------------------

const OPERATOR_CHARS = new Set([";", "&", "|", "\n", "(", ")"]);

/**
 * コマンド文字列を単純コマンドの列に分ける。$(...) とバッククォートの中身は別スクリプトとして
 * nested に積む。完全なシェル文法ではなく、判定に要る分だけを読む。
 */
function splitCommands(script: string, nested: string[]): SimpleCommand[] {
  const commands: SimpleCommand[] = [];
  let words: string[] = [];
  let word = "";
  let inWord = false;
  let heredocs: Heredoc[] = [];

  const endWord = () => {
    if (inWord) words.push(word);
    word = "";
    inWord = false;
  };
  const endCommand = () => {
    endWord();
    if (words.length > 0) commands.push(words);
    words = [];
  };

  for (let i = 0; i < script.length; i++) {
    const c = script[i];
    if (c === "\\") {
      word += script[++i] ?? "";
      inWord = true;
    } else if (c === "'") {
      const end = script.indexOf("'", i + 1);
      const close = end === -1 ? script.length : end;
      word += script.slice(i + 1, close);
      inWord = true;
      i = close;
    } else if (c === '"') {
      i = readDoubleQuoted(script, i + 1, nested, (s) => (word += s));
      inWord = true;
    } else if (c === "$" && script[i + 1] === "(") {
      const close = findClosingParen(script, i + 2);
      nested.push(script.slice(i + 2, close));
      inWord = true;
      i = close;
    } else if (c === "`") {
      const end = script.indexOf("`", i + 1);
      const close = end === -1 ? script.length : end;
      nested.push(script.slice(i + 1, close));
      inWord = true;
      i = close;
    } else if (script.startsWith("<<<", i)) {
      endWord();
      words.push("<<<");
      i += 2;
    } else if (script.startsWith("<<", i)) {
      endWord();
      i = readHeredocDelimiter(script, i + 2, heredocs);
    } else if (c === "\n" && heredocs.length > 0) {
      endCommand();
      i = skipHeredocBodies(script, i + 1, heredocs, nested);
      heredocs = [];
    } else if (OPERATOR_CHARS.has(c)) {
      endCommand();
    } else if (/\s/.test(c)) {
      endWord();
    } else {
      word += c;
      inWord = true;
    }
  }
  endCommand();
  return commands;
}

/**
 * here-document の本文はデータなので読み飛ばす。区切り語と、行頭のタブを許す <<- かどうか、
 * 本文が展開される（区切り語が引用されていない）かどうかを持つ
 */
type Heredoc = { delimiter: string; stripTabs: boolean; expands: boolean };

/** << の直後から区切り語を読み、heredocs に積んで読み終えた位置を返す */
function readHeredocDelimiter(script: string, start: number, heredocs: Heredoc[]): number {
  let i = start;
  const stripTabs = script[i] === "-";
  if (stripTabs) i++;
  while (script[i] === " " || script[i] === "\t") i++;
  let delimiter = "";
  let expands = true;
  for (; i < script.length; i++) {
    const c = script[i];
    if (/\s/.test(c) || OPERATOR_CHARS.has(c)) break;
    if (c === "'" || c === '"' || c === "\\") expands = false;
    else delimiter += c;
  }
  heredocs.push({ delimiter, stripTabs, expands });
  return i - 1;
}

/**
 * 本文の行を区切り語の行まで飛ばし、最後の区切り語の行末の位置を返す。
 * 展開される本文の中のコマンド置換は実行されるので nested に積む
 */
function skipHeredocBodies(
  script: string,
  start: number,
  heredocs: Heredoc[],
  nested: string[],
): number {
  let i = start;
  for (const { delimiter, stripTabs, expands } of heredocs) {
    while (i < script.length) {
      const lineEnd = script.indexOf("\n", i) === -1 ? script.length : script.indexOf("\n", i);
      const line = script.slice(i, lineEnd);
      i = lineEnd + 1;
      if ((stripTabs ? line.replace(/^\t+/, "") : line) === delimiter) break;
      if (expands) collectSubstitutions(line, nested);
    }
  }
  return i - 1;
}

function collectSubstitutions(text: string, nested: string[]): void {
  for (let i = 0; i < text.length; i++) {
    if (text[i] === "\\") {
      i++;
    } else if (text[i] === "$" && text[i + 1] === "(") {
      const close = findClosingParen(text, i + 2);
      nested.push(text.slice(i + 2, close));
      i = close;
    } else if (text[i] === "`") {
      const end = text.indexOf("`", i + 1);
      const close = end === -1 ? text.length : end;
      nested.push(text.slice(i + 1, close));
      i = close;
    }
  }
}

/** 開き " の直後から読み、閉じ " の位置を返す。中の $(...) とバッククォートは nested に積む */
function readDoubleQuoted(
  script: string,
  start: number,
  nested: string[],
  append: (s: string) => void,
): number {
  for (let i = start; i < script.length; i++) {
    const c = script[i];
    if (c === '"') return i;
    if (c === "\\") {
      append(script[++i] ?? "");
    } else if (c === "$" && script[i + 1] === "(") {
      const close = findClosingParen(script, i + 2);
      nested.push(script.slice(i + 2, close));
      i = close;
    } else if (c === "`") {
      const end = script.indexOf("`", i + 1);
      const close = end === -1 ? script.length : end;
      nested.push(script.slice(i + 1, close));
      i = close;
    } else {
      append(c);
    }
  }
  return script.length;
}

function findClosingParen(script: string, start: number): number {
  let depth = 1;
  for (let i = start; i < script.length; i++) {
    if (script[i] === "(") depth++;
    if (script[i] === ")" && --depth === 0) return i;
  }
  return script.length;
}

// ---------------------------------------------------------------------------
// 判定
// ---------------------------------------------------------------------------

/** 後ろに続く語を実行するだけのコマンドと、値を取るオプション */
const WRAPPERS: Record<string, Set<string>> = {
  env: new Set(["-u", "--unset", "-C", "--chdir"]),
  command: new Set(),
  exec: new Set(["-a"]),
  builtin: new Set(),
  nohup: new Set(),
  time: new Set(),
  nice: new Set(["-n", "--adjustment"]),
  sudo: new Set([
    "-u", "--user", "-g", "--group", "-C", "--close-from",
    "-h", "--host", "-p", "--prompt", "-U", "--other-user",
  ]),
  xargs: new Set([
    "-I", "-J", "-L", "-n", "-P", "-R", "-S", "-E", "-s", "-d", "-a",
    "--arg-file", "--delimiter", "--max-args", "--max-procs", "--max-lines", "--max-chars",
  ]),
  timeout: new Set(["-s", "--signal", "-k", "--kill-after"]),
};

/** コマンド名の位置に来ても、それ自体は何も実行しない語 */
const RESERVED_WORDS = new Set(["{", "}", "!", "if", "then", "elif", "else", "while", "until", "do"]);

const REDIRECTION = /^\d*(<<<|>>?|<|>&|<&|>\|)/;

const SHELLS = new Set(["sh", "bash", "zsh", "dash"]);

const SSH_CLIENTS = new Set(["ssh", "scp", "sftp", "sshfs", "autossh", "mosh"]);

/** git のグローバルオプションのうち、次の語を値に取るもの */
const GIT_OPTIONS_WITH_VALUE = new Set([
  "-C",
  "-c",
  "--git-dir",
  "--work-tree",
  "--namespace",
  "--exec-path",
  "--config-env",
  "--super-prefix",
]);

const basename = (path: string) => path.slice(path.lastIndexOf("/") + 1);

/** 止める理由を返す。止めないなら null */
function inspectScript(script: string): string | null {
  const nested: string[] = [];
  for (const command of splitCommands(script, nested)) {
    const reason = inspectCommand(command);
    if (reason) return reason;
  }
  for (const inner of nested) {
    const reason = inspectScript(inner);
    if (reason) return reason;
  }
  return null;
}

function inspectCommand(words: SimpleCommand): string | null {
  let i = 0;
  while (i < words.length) {
    const w = words[i];
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(w) || RESERVED_WORDS.has(w)) {
      i++;
    } else if (REDIRECTION.test(w)) {
      i += w.replace(REDIRECTION, "") === "" ? 2 : 1; // `> file` のように宛先が別の語になる形
    } else {
      break;
    }
  }
  if (i >= words.length) return null;

  const name = basename(words[i]);
  const rest = words.slice(i + 1);

  if (name === "env") {
    const split = splitStringArg(rest);
    if (split !== null) return inspectScript(split);
  }
  const wrapperOptions = WRAPPERS[name];
  if (wrapperOptions) return inspectCommand(skipWrapperArgs(name, rest, wrapperOptions));
  if (name === "eval") return inspectScript(rest.join(" "));
  if (SHELLS.has(name)) {
    const c = rest.findIndex((w) => /^-[a-z]*c[a-z]*$/.test(w));
    return c === -1 || rest[c + 1] === undefined ? null : inspectScript(rest[c + 1]);
  }
  if (name === "git") return isGitPush(rest) ? "git push は禁止されています" : null;
  if (SSH_CLIENTS.has(name)) return `${name} による接続は禁止されています`;
  if (name === "rsync") return usesRemoteShell(rest) ? "ssh 経由の rsync は禁止されています" : null;
  return null;
}

/** env -S / --split-string の値。-S'cmd' や --split-string=cmd のように値が同じ語に付く形も読む */
function splitStringArg(args: string[]): string | null {
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "-S" || arg === "--split-string") return args[i + 1] ?? null;
    if (arg.startsWith("--split-string=")) return arg.slice("--split-string=".length);
    if (/^-S./.test(arg)) return arg.slice(2);
  }
  return null;
}

function skipWrapperArgs(name: string, args: string[], optionsWithValue: Set<string>): string[] {
  let i = 0;
  while (i < args.length) {
    const arg = args[i];
    if (arg === "--") {
      i++;
      break;
    }
    if (arg.startsWith("-")) {
      i += optionsWithValue.has(arg) ? 2 : 1;
    } else if (name === "env" && arg.includes("=")) {
      i++;
    } else {
      break;
    }
  }
  if (name === "timeout") i++; // 実行コマンドの前に制限時間の引数が1つ入る
  return args.slice(i);
}

function isGitPush(args: string[]): boolean {
  let i = 0;
  while (i < args.length && args[i].startsWith("-")) {
    if (args[i] === "--help" || args[i] === "-h") return false;
    i += GIT_OPTIONS_WITH_VALUE.has(args[i]) ? 2 : 1;
  }
  return args[i] === "push";
}

const RSYNC_SHELL_REMOTE = /^([^/:@[]*@)?(\[[^\]]*\]|[^/:[]+):(?!:)/;
const RSYNC_DAEMON_REMOTE = /^([^/:@]*@)?[^/:]+::/;

/**
 * rsync は host:path の引数があるとリモートシェル（既定は ssh）で繋ぐ。host::module は本来 daemon への
 * 直接接続だが、-e/--rsh があるとリモートシェル越しになる
 */
function usesRemoteShell(args: string[]): boolean {
  const hasRsh = args.some((arg) => arg.startsWith("--rsh") || /^-[A-Za-z]*e/.test(arg));
  return args.some(
    (arg) =>
      !arg.startsWith("-") &&
      !arg.startsWith("rsync://") &&
      (RSYNC_SHELL_REMOTE.test(arg) || (hasRsh && RSYNC_DAEMON_REMOTE.test(arg))),
  );
}

// ---------------------------------------------------------------------------
// エントリポイント
// ---------------------------------------------------------------------------

const input: HookInput = JSON.parse(await Bun.stdin.text());
const command = input.tool_input?.command;
if (typeof command === "string") {
  const reason = inspectScript(command);
  if (reason) {
    console.error(`${reason}（guard-remote フック）。必要ならユーザーに実行を依頼してください。`);
    process.exit(2);
  }
}
