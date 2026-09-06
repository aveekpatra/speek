#!/bin/bash
# Speek agent hook. Installed by Speek (Configuration > Advanced > Agent Plugins) to
#   ~/Library/Application Support/Speek/hooks/speek-agent-hook
# Usage:
#   speek-agent-hook claude        Claude Code hook (~/.claude/settings.json), JSON on stdin
#   speek-agent-hook codex         Codex hook (~/.codex/hooks.json), JSON on stdin
#   speek-agent-hook codex <json>  legacy Codex `notify`, JSON as the first argument
#
# For Stop, PermissionRequest and PreToolUse (AskUserQuestion) the hook WAITS: it shows
# the reply panel in Speek and blocks until the user answers there, then returns the
# answer to the agent as hook output (Stop -> {"decision":"block","reason":...}, so the
# agent keeps working on the reply; permissions -> allow/deny). Nothing is typed into a
# terminal. Dismissing the panel lets the agent stop normally.
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
mkdir -p "$STATE_DIR" 2>/dev/null
CWD_HASH=$(printf '%s' "$PWD" | /sbin/md5 -q 2>/dev/null || printf '%s' "$PWD" | md5sum | cut -d' ' -f1)
[ -f "$STATE_DIR/disabled-$CWD_HASH" ] && exit 0

export SPEEK_AGENT_NAME="$AGENT"
export SPEEK_PAYLOAD="$PAYLOAD"
export SPEEK_TERM_APP="${__CFBundleIdentifier:-}"
export SPEEK_TERM_PROGRAM="${TERM_PROGRAM:-}"
export SPEEK_CWD="$PWD"

# Line 1: event name. Line 2: speek:// URL.
PARSED=$(/usr/bin/osascript -l JavaScript -e '
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
function enc(v) { return encodeURIComponent(String(v == null ? "" : v).slice(0, 4000)); }
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
  tool: p.tool_name || "",
  options: options
};
var parts = [];
for (var k in params) { parts.push(k + "=" + enc(params[k])); }
event + "\n" + "speek://agent-update?" + parts.join("&");
' 2>/dev/null)

EVENT="${PARSED%%$'\n'*}"
URL="${PARSED#*$'\n'}"
[ -z "$URL" ] && exit 0

BLOCKING=0
case "$EVENT" in
  Stop|PermissionRequest|PreToolUse) BLOCKING=1 ;;
esac

if [ "$BLOCKING" = "1" ]; then
  REPLY="$STATE_DIR/reply-$$-$RANDOM"
  mkfifo "$REPLY" 2>/dev/null || BLOCKING=0
fi

if [ "$BLOCKING" = "1" ]; then
  URL="$URL&reply=$(printf '%s' "$REPLY" | sed 's/\//%2F/g; s/ /%20/g')"
fi

/usr/bin/open -g "$URL" </dev/null >/dev/null 2>&1

if [ "$BLOCKING" != "1" ]; then
  # Keep a previously configured Codex notify command working (legacy notify mode only).
  PREV_FILE="$HOME/Library/Application Support/Speek/hooks/codex-notify-previous"
  if [ "$AGENT" = "codex" ] && [ -n "${2:-}" ] && [ -s "$PREV_FILE" ]; then
    PREV_CMD="$(cat "$PREV_FILE")"
    [ -n "$PREV_CMD" ] && (eval "$PREV_CMD" "\"\$PAYLOAD\"" >/dev/null 2>&1 &)
  fi
  exit 0
fi

# Wait for Speek's answer (one line on the FIFO). A watchdog releases us before the
# agent's own hook timeout.
WAIT_SECONDS="${SPEEK_REPLY_TIMEOUT:-3300}"
# The watchdog must not inherit our stdout/stdin: the agent waits for EOF on the hook's
# stdout, and a lingering sleep would keep the pipe open long after we answered.
( sleep "$WAIT_SECONDS"; printf 'dismiss\n' > "$REPLY" 2>/dev/null ) </dev/null >/dev/null 2>&1 &
WATCHDOG=$!
disown "$WATCHDOG" 2>/dev/null
IFS= read -r LINE < "$REPLY"
pkill -P "$WATCHDOG" 2>/dev/null
kill "$WATCHDOG" 2>/dev/null
rm -f "$REPLY"

KIND="${LINE%%:*}"
DATA="${LINE#*:}"
[ "$KIND" = "$LINE" ] && DATA=""
TEXT=""
if [ -n "$DATA" ]; then
  TEXT=$(printf '%s' "$DATA" | /usr/bin/base64 -D 2>/dev/null || printf '%s' "$DATA" | /usr/bin/base64 -d 2>/dev/null)
fi

export SPEEK_REPLY_KIND="$KIND" SPEEK_REPLY_TEXT="$TEXT" SPEEK_EVENT="$EVENT"
# SPEEK_PAYLOAD is still exported: the question answer is returned as updatedInput.
/usr/bin/osascript -l JavaScript -e '
ObjC.import("stdlib");
function env(k) { var v = $.getenv(k); return v ? ObjC.unwrap(v) : ""; }
var kind = env("SPEEK_REPLY_KIND"), text = env("SPEEK_REPLY_TEXT"), event = env("SPEEK_EVENT");
var out = null;
if (event === "Stop") {
  if (kind === "reply" && text) out = { decision: "block", reason: text };
} else if (event === "PermissionRequest") {
  if (kind === "allow") out = { hookSpecificOutput: { hookEventName: "PermissionRequest", decision: { behavior: "allow" } } };
  else if (kind === "deny") out = { hookSpecificOutput: { hookEventName: "PermissionRequest", decision: { behavior: "deny", message: text || "Denied by the user in Speek." } } };
  else if (kind === "reply" && text) out = { hookSpecificOutput: { hookEventName: "PermissionRequest", decision: { behavior: "deny", message: text } } };
} else if (event === "PreToolUse") {
  // AskUserQuestion: hand the answer back as pre-filled `answers`, the tool then
  // auto-approves instead of showing its picker in the terminal.
  var answer = "";
  if (kind === "option" && text) answer = text;
  else if (kind === "reply" && text) answer = text;
  if (answer) {
    var p = {};
    try { p = JSON.parse(env("SPEEK_PAYLOAD") || "{}"); } catch (e) { p = {}; }
    var input = (p && p.tool_input) ? p.tool_input : {};
    var answers = {};
    var qs = (input.questions && input.questions.length) ? input.questions : [];
    if (qs.length) {
      qs.forEach(function (q, i) { answers[q.question || ("q" + i)] = answer; });
    } else {
      answers[input.question || "question"] = answer;
    }
    var updated = {};
    for (var k in input) updated[k] = input[k];
    updated.answers = answers;
    out = { hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "allow", updatedInput: updated } };
  }
}
out ? JSON.stringify(out) : "";
' 2>/dev/null

exit 0
