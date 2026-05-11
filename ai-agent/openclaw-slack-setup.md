# OpenClaw Slack App Setup

## Overview

OpenClaw uses Slack's **Socket Mode** (no public URL needed). The easiest way to configure the Slack app is via the App Manifest — it sets all scopes and event subscriptions in one paste.

---

## Step 1: Create the Slack App from Manifest

1. Go to [api.slack.com/apps](https://api.slack.com/apps) → **Create New App** → **From an app manifest**
2. Select your workspace
3. Paste the manifest JSON below (replace `luffy` with your preferred bot name)

```json
{
  "display_information": {
    "name": "luffy",
    "description": "luffy connector for OpenClaw"
  },
  "features": {
    "bot_user": {
      "display_name": "luffy",
      "always_online": true
    },
    "app_home": {
      "home_tab_enabled": true,
      "messages_tab_enabled": true,
      "messages_tab_read_only_enabled": false
    },
    "slash_commands": [
      {
        "command": "/openclaw",
        "description": "Send a message to OpenClaw",
        "should_escape": false
      }
    ]
  },
  "oauth_config": {
    "scopes": {
      "bot": [
        "app_mentions:read",
        "assistant:write",
        "channels:history",
        "channels:read",
        "chat:write",
        "commands",
        "emoji:read",
        "files:read",
        "files:write",
        "groups:history",
        "groups:read",
        "im:history",
        "im:read",
        "im:write",
        "mpim:history",
        "mpim:read",
        "mpim:write",
        "pins:read",
        "pins:write",
        "reactions:read",
        "reactions:write",
        "usergroups:read",
        "users:read"
      ]
    }
  },
  "settings": {
    "socket_mode_enabled": true,
    "event_subscriptions": {
      "bot_events": [
        "app_home_opened",
        "app_mention",
        "channel_rename",
        "member_joined_channel",
        "member_left_channel",
        "message.channels",
        "message.groups",
        "message.im",
        "message.mpim",
        "pin_added",
        "pin_removed",
        "reaction_added",
        "reaction_removed"
      ]
    }
  }
}
```

4. Review and click **Create**

---

## Step 2: Enable Socket Mode and Get the App Token

1. In your app settings → **Socket Mode** → toggle **Enable Socket Mode**
2. When prompted, create an App-Level Token:
   - Name: e.g. `openclaw-socket`
   - Scope: `connections:write`
3. Copy the token — this is your `xapp-...` token

---

## Step 3: Install the App and Get the Bot Token

1. Go to **OAuth & Permissions** → **Install to Workspace**
2. Authorize the app
3. Copy the **Bot User OAuth Token** — this is your `xoxb-...` token

---

## Step 4: Configure OpenClaw

Edit `~/.openclaw/openclaw.json` and update the `channels.slack` section:

```json
"channels": {
  "slack": {
    "enabled": true,
    "botToken": "xoxb-...",
    "appToken": "xapp-1-...",
    "mode": "socket"
  }
}
```

Then restart the gateway:

```bash
systemctl --user restart openclaw-gateway
```

Verify with:

```bash
openclaw channels status --deep
```

---

## Updating an Existing App

If the app already exists but is missing scopes (e.g. `im:history` was absent):

1. Go to [api.slack.com/apps](https://api.slack.com/apps) → select your app → **App Manifest**
2. Replace the manifest with the JSON above and save
3. **OAuth & Permissions** → **Reinstall to Workspace** (required after any scope change)
4. Copy the new `xoxb-...` bot token and update `~/.openclaw/openclaw.json`
5. Restart the gateway

> Note: The `xapp-...` app token does **not** change on reinstall — only the bot token does.

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Bot connected but no reaction to DMs | `im:history` scope missing or `message.im` event not subscribed |
| Socket disconnects immediately | `xapp-` token invalid or `connections:write` scope missing |
| Bot responds in channels but not DMs | `im:history` / `message.im` missing |
| `openclaw channels logs` shows no lines | Events not reaching OpenClaw — check scopes and event subscriptions |

Manifest source: `buildSlackManifest()` in `/usr/lib/node_modules/openclaw/dist/setup-core-DlXoQQp0.js`
