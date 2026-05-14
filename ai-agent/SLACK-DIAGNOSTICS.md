# Slack Channel Diagnostics

Quick reference for diagnosing why openclaw is not receiving or replying to Slack messages.

---

## 1. Check channel status

```bash
openclaw channels status --deep
```

**Good output:**
```
Gateway reachable.
- Slack default: enabled, configured, running, connected, in:Xs ago, bot:config, app:config, health:healthy
```

**Warning signs:**
- `in:Xh ago` — last inbound was hours ago; events may not be arriving
- `in:` absent — no inbound event received since last restart
- `health:degraded` — Slack connection is unhealthy

---

## 2. Check gateway logs

```bash
journalctl --user -u openclaw-gateway -n 100 --no-pager
```

Also check the file log for agent/send activity:

```bash
openclaw channels logs
```

**Key log lines to look for:**

| Log line | Meaning |
|---|---|
| `slack socket mode connected` | Slack Socket Mode handshake succeeded |
| `slack users resolved: …` | Bot resolved Slack user IDs — healthy |
| `socket disconnected (disconnect); reconnecting in 2s (attempt 1/12)` | Normal Slack-initiated periodic disconnect (every ~5h) |
| `skipping channel message` | Bot received a channel event but ignored it — see §5 |
| `embedded run agent end: isError=true … Connection error` | LLM backend unreachable — see LLM-DIAGNOSTICS.md |
| `Invalid config at openclaw.json` | Bad config prevented startup — see §6 |

---

## 3. Check Slack app scopes and event subscriptions

If the bot connects but events are not arriving, the Slack app manifest may be missing scopes.

1. Go to [api.slack.com/apps](https://api.slack.com/apps) → your app → **App Manifest**
2. Confirm the manifest matches `openclaw-slack-setup.md` (includes `message.channels`, `app_mention`, `chat:write`, etc.)
3. After any scope change: **OAuth & Permissions → Reinstall to Workspace**
4. Copy the new `xoxb-…` bot token and update `~/.openclaw/openclaw.json`
5. Restart: `systemctl --user restart openclaw-gateway`

> The `xapp-…` app token does **not** change on reinstall — only the `xoxb-…` bot token does.

---

## 4. Invite the bot to the channel

The bot must be a member of any channel it replies to. Without this, `chat:write` calls fail silently.

In the target Slack channel:
```
/invite @luffy
```

(Replace `luffy` with your bot's display name.)

---

## 5. Fix: replies appear in dashboard but not in Slack

**Symptom:** A session like `slack:XXXX#general` is created and the agent replies in the openclaw control UI, but nothing appears in Slack.

**Cause:** `messages.groupChat.visibleReplies` is set to `"message_tool"` in `~/.openclaw/openclaw.json`.

**Fix:** Change it to `true`:

```json
"messages": {
  "groupChat": {
    "visibleReplies": true
  }
}
```

Valid values: `"automatic"`, `"message_tool"`, `true`, `false`

Then restart the gateway:
```bash
systemctl --user restart openclaw-gateway
```

---

## 6. Fix invalid config (gateway fails to start)

If the gateway fails to start with `Invalid config at openclaw.json`:

```bash
openclaw doctor --fix
```

Then restart:
```bash
systemctl --user restart openclaw-gateway
```

Stability crash reports are in:
```
~/.openclaw/logs/stability/
```

---

## 7. Check gateway event loop health

```bash
openclaw channels status --deep
```

If `Gateway event loop degraded` appears with `eventLoopUtilization=1`:

- Check overall system CPU: `ps aux --sort=-%cpu | head -10`
- If the machine is under heavy load from other processes, the metric may be a false positive — verify by checking actual response times in the log (should be under ~500ms for `channels.status`)
- If the gateway has been running for days with prior LLM errors, restart it to clear accumulated state

---

## 8. Slack socket disconnects every ~5 hours

Slack-initiated periodic disconnects are normal for Socket Mode. The log line:

```
slack socket disconnected (disconnect); reconnecting in 2s (attempt 1/12)
```

is expected. The bot reconnects automatically. No action needed unless it never reconnects (check `in:` timestamp in `channels status --deep`).

---

## 9. Fix: agent replies but tool calls (bash/exec) never run

**Symptom:** The agent responds in Slack but produces XML output in the dashboard showing `<tool_calls><invoke name="exec">…</invoke></tool_calls>` — the bash code is written out but never executed.

**Cause A — `ownerAllowFrom` ID mismatch:** Exec in group sessions requires the sender to be recognized as an owner. If the Slack user ID in `commands.ownerAllowFrom` doesn't exactly match the resolved user ID, exec is silently blocked.

Check the resolved ID in the gateway log:
```
slack users resolved: UGF82QCLC→Jim (id:UGF82QCLC)
```

Then verify `~/.openclaw/openclaw.json`:
```json
"commands": {
  "ownerAllowFrom": ["slack:UGF82QCLC"]
}
```

The value must be `slack:` + the exact Slack user ID (case-sensitive, no trailing/missing characters).

**Cause B — exec approval policy:** The `exec.ask` default in group channels is stricter. The approval dialog appears in the openclaw control UI, not in Slack, so exec never runs from the Slack side.

Fix by setting exec policy explicitly:
```json
"tools": {
  "exec": {
    "security": "full",
    "ask": "off"
  }
}
```

> **Note:** `ask: "off"` with `groupPolicy: "open"` means anyone in the channel can trigger exec. Tighten `groupPolicy` or keep `ask: "on-miss"` with an allowlist if the channel is not fully trusted.

After either fix, restart the gateway:
```bash
systemctl --user restart openclaw-gateway
```

---

## Common failure patterns

| Symptom | Likely cause | Fix |
|---|---|---|
| `in:Xh ago` and bot is silent | Events not arriving | Check scopes and event subscriptions (§3) |
| Bot responds in DMs but not channels | Bot not invited to channel | `/invite @luffy` in the channel (§4) |
| Reply shows in dashboard but not Slack | `visibleReplies: "message_tool"` | Set `visibleReplies: true` in config (§5) |
| XML tool calls shown in dashboard, never executed | `ownerAllowFrom` ID mismatch or `exec.ask` policy | Fix user ID and/or exec policy (§9) |
| `socket disconnected … attempt 1/12` | Normal Slack periodic disconnect | No action needed (§8) |
| Gateway fails to start | Invalid `openclaw.json` | `openclaw doctor --fix` (§6) |
| Agent gets no LLM response | Vertex AI proxy down | See `LLM-DIAGNOSTICS.md` |

---

## Architecture overview

```
Slack  →  Socket Mode  →  openclaw gateway (port 18789)
                               └── [slack] channel provider
                                       ├── receives: app_mention, message.channels, message.im, …
                                       └── sends: chat:write → Slack API
```

Config: `~/.openclaw/openclaw.json` → `channels.slack`
Slack app setup: `ai-agent/openclaw-slack-setup.md`
LLM connectivity: `ai-agent/LLM-DIAGNOSTICS.md`
