#!/bin/bash
# Speek agent hook. Installed by Speek (Configuration > Advanced > Agent Plugins) to
#   ~/Library/Application Support/Speek/hooks/speek-agent-hook
# Usage:
#   speek-agent-hook claude        Claude Code hook (~/.claude/settings.json), JSON on stdin
#   speek-agent-hook codex         Codex hook (~/.codex/hooks.json), JSON on stdin
#   speek-agent-hook codex <json>  legacy Codex `notify`, JSON as the first argument
# It never blocks the agent: it forwards the event to Speek through the speek:// URL
# scheme and exits 0 immediately.
#
# Mute per project with the /speek skill (or SPEEK_AGENT=0): it creates
#   /tmp/speek-agent/disabled-<md5 of cwd>

AGENT="${1:-claude}"
if [ "$AGENT" = "codex" ] && [ -n "${2:-}" ]; then
  PAYLOAD="$2"
else
  PAYLOAD="$(cat 2>/dev/null)"
fi

[ "${SPEEK_AGENT:-1}" = "0" ] && exit 0
STATE_DIR="${SPEEK_AGENT_STATE_DIR:-/tmp/speek-agent}"
CWD_HASH=$(printf '%s' "$PWD" | /sbin/md5 -q 2>/dev/null || printf '%s' "$PWD" | md5sum | cut -d' ' -f1)
[ -f "$STATE_DIR/disabled-$CWD_HASH" ] && exit 0

export SPEEK_AGENT_NAME="$AGENT"
export SPEEK_PAYLOAD="$PAYLOAD"
export SPEEK_TERM_APP="${__CFBundleIdentifier:-}"
export SPEEK_TERM_PROGRAM="${TERM_PROGRAM:-}"
export SPEEK_CWD="$PWD"

URL=$(/usr/bin/osascript -l JavaScript -e '
ObjC.import("stdlib");
function env(k) { var v = $.getenv(k); return v ? ObjC.unwrap(v) : ""; }
var p = {};
try { p = JSON.parse(env("SPEEK_PAYLOAD") || "{}"); } catch (e) { p = {}; }
var agent = env("SPEEK_AGENT_NAME");
var event = p.hook_event_name || p.type || "";
var message = p.message || p["last-assistant-message"] || p.last_assistant_message || "";
var options = "";
if (event === "PreToolUse" && p.tool_input) {
  if (p.tool_input.questions && p.tool_input.questions.length) {
    message = p.tool_input.questions.map(function (q) { return q.question; }).join("\n");
    var first = p.tool_input.questions[0];
    if (first && first.options && first.options.length) {
      options = first.options.map(function (o) { return (o && o.label) ? o.label : String(o); }).join("\n");
    }
  } else if (p.tool_input.question) {
    message = p.tool_input.question;
  }
}
if (event === "PermissionRequest") {
  var tool = p.tool_name || "a tool";
  var detail = "";
  try { detail = p.tool_input && (p.tool_input.command || p.tool_input.file_path || p.tool_input.description || ""); } catch (e) {}
  message = "Permission needed for " + tool + (detail ? ": " + String(detail).slice(0, 300) : "");
}
function enc(v) { return encodeURIComponent(String(v == null ? "" : v).slice(0, 2000)); }
var params = {
  agent: agent,
  event: event,
  message: message,
  session: p.session_id || p["turn-id"] || p.turn_id || "",
  cwd: p.cwd || env("SPEEK_CWD"),
  app: env("SPEEK_TERM_APP"),
  term: env("SPEEK_TERM_PROGRAM"),
  notification: p.notification_type || "",
  permission: p.permission_mode || "",
  options: options
};
var parts = [];
for (var k in params) { parts.push(k + "=" + enc(params[k])); }
"speek://agent-update?" + parts.join("&");
' 2>/dev/null)

if [ -n "$URL" ]; then
  /usr/bin/open -g "$URL" >/dev/null 2>&1 &
fi

# Keep a previously configured Codex notify command working (legacy notify mode only).
PREV_FILE="$HOME/Library/Application Support/Speek/hooks/codex-notify-previous"
if [ "$AGENT" = "codex" ] && [ -n "${2:-}" ] && [ -s "$PREV_FILE" ]; then
  PREV_CMD="$(cat "$PREV_FILE")"
  if [ -n "$PREV_CMD" ]; then
    (eval "$PREV_CMD" "\"\$PAYLOAD\"" >/dev/null 2>&1 &)
  fi
fi

exit 0
