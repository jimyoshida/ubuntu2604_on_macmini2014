# LLM Connection Diagnostics

Quick reference for diagnosing why openclaw cannot reach LLM models.

---

## 1. Test a model directly

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

## 2. List available models and providers

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

## 3. Test each provider independently

Test a known-good model for each provider to isolate which provider is broken:

| Provider | Test command |
|---|---|
| `vertex` (localhost proxy) | `openclaw infer model run --model "vertex/claude-sonnet-4-5@20250929" --prompt "ping" --local` |
| `google-vertex` (direct GCP) | `openclaw infer model run --model "google-vertex/gemini-2.5-flash" --prompt "ping" --local` |
| `anthropic-vertex` (direct Vertex) | `openclaw infer model run --model "claude-sonnet-4-6" --prompt "ping" --local` |

---

## 4. Check the vertex-ai-proxy (port 8001)

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

## 5. Check the openclaw gateway (port 18789)

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

## 6. Check Google Cloud authentication

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

## 7. Run the openclaw doctor

Catches config errors, missing auth, and misconfigured channels:

```bash
openclaw doctor
```

For auto-fixes:
```bash
openclaw doctor --fix
```

---

## 8. Check openclaw logs

```bash
openclaw logs
```

Stability snapshots (crash reports) are in:
```
~/.openclaw/logs/stability/
```

---

## Common failure patterns

| Symptom | Likely cause | Fix |
|---|---|---|
| `No text output returned for provider "vertex"` | `vertex-ai-proxy` not running | `vertex-ai-proxy start` |
| `Unknown model: <id>` | Model ID or provider prefix wrong | Run `openclaw infer model list` to get exact IDs |
| `gateway.startup_failed` in stability logs | Invalid `openclaw.json` | `openclaw doctor --fix` |
| All providers fail | gcloud ADC expired | `gcloud auth application-default login` |
| Gateway not responding | `openclaw-gateway.service` down | `systemctl restart openclaw-gateway.service` |

---

## Architecture overview

```
openclaw gateway (port 18789)
    └── vertex provider  →  vertex-ai-proxy (port 8001)  →  Google Vertex AI (Claude)
    └── google-vertex    →  Google Vertex AI (Gemini) via gcloud ADC
    └── anthropic-vertex →  Google Vertex AI (Claude) via gcloud ADC
```

The `vertex-ai-proxy` daemon is separate from the openclaw gateway and must be running independently. It does not restart automatically — add it to a startup script or systemd user service if reboots are common.
