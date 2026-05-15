# OpenClaw Diagnostics

Quick reference for diagnosing openclaw connectivity issues.

- [LLM / Model connectivity](#llm--model-connectivity)
- [Slack channel connectivity](#slack-channel-connectivity)

---

## LLM / Model connectivity

### 1. Test a model directly

The fastest first check. Run a one-shot prompt against a specific model:

```bash
openclaw infer model run --model "vertex/claude-sonnet-4-5@20250929" --prompt "ping" --local
```

**Good output:**
```
model.run via local
provider: vertex
model: claude-sonnet-4-5@20250929
outputs: 1
pong
```

**Bad output:**
```
Error: No text output returned for provider "vertex" model "claude-sonnet-4-5@20250929".
```

If it fails, continue to the steps below to find the broken layer.

---

### 2. List available models and providers

```bash
openclaw infer model list
```

Shows all models openclaw knows about. Models are grouped by provider — check which provider your failing model belongs to:

```bash
openclaw infer model list | grep -i vertex
```

To see the current default model and its provider:

```bash
openclaw models status
```

---

### 3. Test each provider independently

Test a known-good model for each provider to isolate which provider is broken:

| Provider | Test command |
|---|---|
| `vertex` (localhost proxy) | `openclaw infer model run --model "vertex/claude-sonnet-4-5@20250929" --prompt "ping" --local` |
| `google-vertex` (direct GCP) | `openclaw infer model run --model "google-vertex/gemini-2.5-flash" --prompt "ping" --local` |
| `anthropic-vertex` (direct Vertex) | `openclaw infer model run --model "claude-sonnet-4-6" --prompt "ping" --local` |

---

### 4. Check the vertex-ai-proxy (port 8001)

The `vertex` provider routes through a local proxy at `http://localhost:8001/v1`.
If that proxy is down, all Claude models via `vertex` will fail.

**Check status:**
```bash
vertex-ai-proxy status
```

Look for:
- `✓ Running` — proxy is healthy
- `✗ Not running (stale PID: XXXXX)` — proxy crashed, needs restart

**Start the proxy:**
```bash
vertex-ai-proxy start
```

**View logs if it fails to start:**
```bash
vertex-ai-proxy logs
```

**Verify port 8001 is now listening:**
```bash
ss -tlnp | grep 8001
```

---

### 5. Check the openclaw gateway (port 18789)

The gateway is the main openclaw process. If it's down, nothing works.

```bash
openclaw health
```

```bash
ss -tlnp | grep 18789
```

To restart the gateway service:
```bash
systemctl restart openclaw-gateway.service
```

---

### 6. Check Google Cloud authentication

The `vertex-ai-proxy` and `google-vertex` provider both need valid gcloud ADC credentials.

```bash
gcloud auth application-default print-access-token
```

If this errors (e.g. `Could not automatically determine credentials`), refresh:
```bash
gcloud auth application-default login
```

Check the active project:
```bash
gcloud config list
```

Expected project: `gsol2-457003`

---

### 7. Run the openclaw doctor

Catches config errors, missing auth, and misconfigured channels:

```bash
openclaw doctor
```

For auto-fixes:
```bash
openclaw doctor --fix
```

---

### 8. Check openclaw logs

```bash
openclaw logs
```

Stability snapshots (crash reports) are in:
```
~/.openclaw/logs/stability/
```

---

### Common LLM failure patterns

| Symptom | Likely cause | Fix |
|---|---|---|
| `No text output returned for provider "vertex"` | `vertex-ai-proxy` not running | `vertex-ai-proxy start` |
| `Unknown model: <id>` | Model ID or provider prefix wrong | Run `openclaw infer model list` to get exact IDs |
| `gateway.startup_failed` in stability logs | Invalid `openclaw.json` | `openclaw doctor --fix` |
| All providers fail | gcloud ADC expired | `gcloud auth application-default login` |
| Gateway not responding | `openclaw-gateway.service` down | `systemctl restart openclaw-gateway.service` |

---

### LLM architecture overview

```
openclaw gateway (port 18789)
    └── vertex provider  →  vertex-ai-proxy (port 8001)  →  Google Vertex AI (Claude)
    └── google-vertex    →  Google Vertex AI (Gemini) via gcloud ADC
    └── anthropic-vertex →  Google Vertex AI (Claude) via gcloud ADC
```

The `vertex-ai-proxy` daemon is separate from the openclaw gateway and must be running independently. It does not restart automatically — add it to a startup script or systemd user service if reboots are common.

---

## Slack channel connectivity

### 1. Check channel status

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

### 2. Check gateway logs

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
| `embedded run agent end: isError=true … Connection error` | LLM backend unreachable — see [LLM / Model connectivity](#llm--model-connectivity) |
| `Invalid config at openclaw.json` | Bad config prevented startup — see §6 |

---

### 3. Check Slack app scopes and event subscriptions

If the bot connects but events are not arriving, the Slack app manifest may be missing scopes.

1. Go to [api.slack.com/apps](https://api.slack.com/apps) → your app → **App Manifest**
2. Confirm the manifest matches `openclaw-slack-setup.md` (includes `message.channels`, `app_mention`, `chat:write`, etc.)
3. After any scope change: **OAuth & Permissions → Reinstall to Workspace**
4. Copy the new `xoxb-…` bot token and update `~/.openclaw/openclaw.json`
5. Restart: `systemctl --user restart openclaw-gateway`

> The `xapp-…` app token does **not** change on reinstall — only the `xoxb-…` bot token does.

---

### 4. Invite the bot to the channel

The bot must be a member of any channel it replies to. Without this, `chat:write` calls fail silently.

In the target Slack channel:
```
/invite @luffy
```

(Replace `luffy` with your bot's display name.)

---

### 5. Fix: replies appear in dashboard but not in Slack

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

### 6. Fix invalid config (gateway fails to start)

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

### 7. Check gateway event loop health

```bash
openclaw channels status --deep
```

If `Gateway event loop degraded` appears with `eventLoopUtilization=1`:

- Check overall system CPU: `ps aux --sort=-%cpu | head -10`
- If the machine is under heavy load from other processes, the metric may be a false positive — verify by checking actual response times in the log (should be under ~500ms for `channels.status`)
- If the gateway has been running for days with prior LLM errors, restart it to clear accumulated state

---

### 8. Slack socket disconnects every ~5 hours

Slack-initiated periodic disconnects are normal for Socket Mode. The log line:

```
slack socket disconnected (disconnect); reconnecting in 2s (attempt 1/12)
```

is expected. The bot reconnects automatically. No action needed unless it never reconnects (check `in:` timestamp in `channels status --deep`).

---

### 9. Fix: agent replies but tool calls (bash/exec) never run

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

### Common Slack failure patterns

| Symptom | Likely cause | Fix |
|---|---|---|
| `in:Xh ago` and bot is silent | Events not arriving | Check scopes and event subscriptions (§3) |
| Bot responds in DMs but not channels | Bot not invited to channel | `/invite @luffy` in the channel (§4) |
| Reply shows in dashboard but not Slack | `visibleReplies: "message_tool"` | Set `visibleReplies: true` in config (§5) |
| XML tool calls shown in dashboard, never executed | `ownerAllowFrom` ID mismatch or `exec.ask` policy | Fix user ID and/or exec policy (§9) |
| `socket disconnected … attempt 1/12` | Normal Slack periodic disconnect | No action needed (§8) |
| Gateway fails to start | Invalid `openclaw.json` | `openclaw doctor --fix` (§6) |
| Agent gets no LLM response | Vertex AI proxy down | See [LLM / Model connectivity](#llm--model-connectivity) |

---

### Slack architecture overview

```
Slack  →  Socket Mode  →  openclaw gateway (port 18789)
                               └── [slack] channel provider
                                       ├── receives: app_mention, message.channels, message.im, …
                                       └── sends: chat:write → Slack API
```

Config: `~/.openclaw/openclaw.json` → `channels.slack`
Slack app setup: `ai-agent/openclaw-slack-setup.md`
