#!/usr/bin/env bash
set -euo pipefail

# NocturnalZone Hugoテーマのプレビュー画像（images/screenshot.png、images/tn.png）を再生成する。
# exampleSiteをローカルのhugo serverで配信し、ヘッドレスChromeで撮影する。
# 画面操作は行わないため、追跡中の画像を書き換えずに--output-dirで試せる。

usage() {
    cat <<'USAGE'
Regenerate images/screenshot.png (1500x1000) and images/tn.png (900x600) with the
bundled example site and headless Chrome.

Usage:
  scripts/screenshot.sh [options]

Options:
  -o, --output-dir DIR  Output directory for screenshot.png and tn.png. Default: images/
      --port PORT       Port for the hugo server. Default: 1314
  -h, --help            Show this help and exit.

Environment:
  CHROME  Chrome executable.
          Default: /Applications/Google Chrome.app/Contents/MacOS/Google Chrome

Requirements:
  - Hugo is installed (`hugo version`).
  - Google Chrome is installed.
USAGE
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

display_path() {
    local path="$1"
    case "$path" in
    "$repo_root"/*) printf '%s\n' "${path#"$repo_root"/}" ;;
    *) printf '%s\n' "$path" ;;
    esac
}

# 撮影対象はexampleSiteのトップページのみ。サイズは列挙のとおり固定する。
window_size="1500,1000"
# sipsの-zは高さと幅を別引数で受け取るため、tn.pngは高さ600・幅900になる。
thumb_height=600
thumb_width=900

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_dir/.." && pwd -P)"

output_dir="$repo_root/images"
port=1314
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

while [ "$#" -gt 0 ]; do
    case "$1" in
    -o | --output-dir)
        [ "$#" -ge 2 ] || die "$1 requires a directory"
        output_dir="$2"
        shift 2
        ;;
    --port)
        [ "$#" -ge 2 ] || die "$1 requires a port"
        port="$2"
        shift 2
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        die "unknown argument: $1"
        ;;
    esac
done

[ -x "$chrome" ] || die "Chrome not found: $chrome (set CHROME to override)"
command -v hugo >/dev/null 2>&1 || die "hugo not found"

tmp_dir=""
server_pid=""

stop_server() {
    [ -n "$server_pid" ] || return 0
    if kill -0 "$server_pid" 2>/dev/null; then
        # hugo serverは単一プロセスなのでpidを直接止める。
        # SIGTERMで終了させることで.hugo_build.lockも残さない。
        kill "$server_pid" 2>/dev/null || true
        local waited=0
        while kill -0 "$server_pid" 2>/dev/null && [ "$waited" -lt 50 ]; do
            sleep 0.1
            waited=$((waited + 1))
        done
        kill -9 "$server_pid" 2>/dev/null || true
    fi
    server_pid=""
}

cleanup() {
    local status=$?
    stop_server
    if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
        if [ -x /usr/bin/trash ]; then
            /usr/bin/trash "$tmp_dir" >/dev/null 2>&1 ||
                printf 'warning: could not move %s to Trash\n' "$tmp_dir" >&2
        else
            printf 'warning: /usr/bin/trash not found; leaving %s\n' "$tmp_dir" >&2
        fi
    fi
    return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# 到達確認はcurlで行い、固定sleepで代用しない。期限を過ぎたら失敗として扱う。
wait_for_http() {
    local url="$1" timeout="$2" start=$SECONDS
    while ! curl -fsS -o /dev/null --max-time 5 "$url" 2>/dev/null; do
        [ $((SECONDS - start)) -lt "$timeout" ] || return 1
        sleep 0.5
    done
}

tmp_dir="$(mktemp -d)"
server_log="$tmp_dir/hugo-server.log"
shot="$tmp_dir/screenshot.png"
thumb="$tmp_dir/tn.png"

cd "$repo_root"

# 別のプロセスが同じportで応答していると、その画面を誤って撮影してしまう。
if curl -fsS -o /dev/null --max-time 2 "http://127.0.0.1:$port/" 2>/dev/null; then
    die "port $port is already in use; stop that server or pass --port"
fi

# 子プロセス出力はlogへ隔離し、stdoutには要約だけを出す。
hugo server \
    --source exampleSite \
    --themesDir ../.. \
    --theme nocturnalzone-hugo-theme \
    --port "$port" \
    --bind 127.0.0.1 >"$server_log" 2>&1 &
server_pid=$!

if ! wait_for_http "http://127.0.0.1:$port/" 120; then
    printf 'error: hugo server did not respond on http://127.0.0.1:%s/\n' "$port" >&2
    tail -n 40 "$server_log" >&2 || true
    exit 1
fi
# 応答したのが自分で起動したserverであることを確かめる。
kill -0 "$server_pid" 2>/dev/null || die "hugo server exited; see the log above"

if ! "$chrome" --headless --disable-gpu --no-first-run --hide-scrollbars \
    --user-data-dir="$tmp_dir/chrome-profile" \
    --screenshot="$shot" --window-size="$window_size" \
    "http://127.0.0.1:$port/" >"$tmp_dir/chrome.log" 2>&1; then
    printf 'error: headless Chrome failed\n' >&2
    tail -n 20 "$tmp_dir/chrome.log" >&2 || true
    exit 1
fi

[ -s "$shot" ] || die "headless Chrome did not write $shot"

sips -z "$thumb_height" "$thumb_width" "$shot" --out "$thumb" >/dev/null
[ -s "$thumb" ] || die "sips did not write $thumb"

mkdir -p "$output_dir"
cp "$shot" "$output_dir/screenshot.png"
cp "$thumb" "$output_dir/tn.png"

printf 'wrote %s (%s)\n' "$(display_path "$output_dir/screenshot.png")" "$window_size"
printf 'wrote %s (%sx%s)\n' "$(display_path "$output_dir/tn.png")" "$thumb_width" "$thumb_height"
