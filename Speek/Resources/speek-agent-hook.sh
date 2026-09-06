#!/bin/bash
# Speek agent hook. Installed by Speek (Configuration > Advanced > Agent Plugins) to
#   ~/Library/Application Support/Speek/hooks/speek-agent-hook
# Usage:
#   speek-agent-hook claude        (Claude Code hook: JSON payload on stdin)
#   speek-agent-hook codex <json>  (Codex notify: JSON payload as the first argument)
# It never blocks the agent: it forwards the event to Speek through the speek:// URL
# scheme and exits 0 immediately.

AGENT="${1:-claude}"
if [ "$AGENT" = "codex" ]; then
  PAYLOAD="${2:-}"
else
  PAYLOAD="$(cat 2>/dev/null)"
fi

export SPEEK_AGENT="$AGENT"
export SPEEK_PAYLOAD="$PAYLOAD"
export SPEEK_TERM_APP="${__CFBundleIdentifier:-}"
export SPEEK_TERM_PROGRAM="${TERM_PROGRAM:-}"
export SPEEK_CWD="$PWD"

URL=$(/usr/bin/osascript -l JavaScript -e '
ObjC.import("stdlib");
function env(k) { var v = $.getenv(k); return v ? ObjC.unwrap(v) : ""; }
var p = {};
try { p = JSON.parse(env("SPEEK_PAYLOAD") || "{}"); } catch (e) { p = {}; }
var agent = env("SPEEK_AGENT");
var event = p.hook_event_name || p.type || "";
var message = p.message || p["last-assistant-message"] || p.last_assistant_message || "";
if (event === "PreToolUse" && p.tool_input) {
  if (p.tool_input.questions && p.tool_input.questions.length) {
    message = p.tool_input.questions.map(function (q) { return q.question; }).join("\n");
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
  permission: p.permission_mode || ""
};
var parts = [];
for (var k in params) { parts.push(k + "=" + enc(params[k])); }
"speek://agent-update?" + parts.join("&");
' 2>/dev/null)

if [ -n "$URL" ]; then
  /usr/bin/open -g "$URL" >/dev/null 2>&1 &
fi

# Keep a previously configured Codex notify command working.
PREV_FILE="$HOME/Library/Application Support/Speek/hooks/codex-notify-previous"
if [ "$AGENT" = "codex" ] && [ -s "$PREV_FILE" ]; then
  PREV_CMD="$(cat "$PREV_FILE")"
  if [ -n "$PREV_CMD" ]; then
    (eval "$PREV_CMD" "\"\$PAYLOAD\"" >/dev/null 2>&1 &)
  fi
fi

exit 0
