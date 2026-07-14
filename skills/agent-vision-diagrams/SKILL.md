---
name: agent-vision-diagrams
description: Create and iterate on shareable visual diagrams (architecture maps, flowcharts, state machines, class/domain models, mindmaps, dependency maps) via the Agent Vision MCP server or its HTTP action API. Use when the user asks for a diagram, visualization, or "draw this out" during a conversation, or when the user hands you an Agent Vision app URL + connection token.
---

# Agent Vision — diagrams for the user

Agent Vision is a hosted diagram app. You write a small JSON document (the
**spec** — a DSL), the app renders it (2D now, isometric later), stores every
change as an immutable **revision**, and returns a public **share URL** plus a
rendered **PNG** so you can show the user immediately.

This installed skill is a thin connection recipe. **The full DSL, the color /
idiom grammar, worked examples, ops-patch reference, icon catalog, and warning
list live in the hosted, canonical skill doc** — fetch it once at the start of a
diagramming session and follow it:

    <app-url>/skill.md   (ask the user for their Agent Vision app URL)

(Replace the host with whatever app URL the user gave you; the skill doc lives
at `<app-url>/skill.md`.)

## Connecting (given only the user's app `<url>`)

**Step 0 — check the environment first:** if `AGENT_NATIVE_VISION_URL` and
`AGENT_NATIVE_VISION_TOKEN` env vars are set (provisioned containers), use them
and skip all auth below — bearer header on every call, done.

**Primary — device flow, you drive it.** No pre-minted token, no password:

1. `POST <url>/_agent-native/mcp/connect/device/start` (empty JSON body, no
   auth) → `{ device_code, user_code, verification_uri_complete, interval,
   expires_in }`.
2. Tell the user in chat: "Open `<verification_uri_complete>` and click
   **Authorize this device** (code `<user_code>`)." Any device where they're
   already logged in works.
3. `POST <url>/_agent-native/mcp/connect/device/poll` with
   `{ "device_code": "<device_code>" }` every `interval` seconds until it
   returns `approved` → `{ token, mcpUrl, ... }` (`pending` = keep going;
   `expired`/`consumed` = restart at step 1).
4. Use the token exactly as below.

**Fallback — user-minted token:** the user logs in, opens
`<url>/_agent-native/mcp/connect`, clicks **Create connection token**, and
pastes `{ url, token }` to you. Tokens are per-user, scoped, expiry-bound, and
revocable from that same page.

**MCP clients (Claude Code, etc.):**

```
claude mcp add --transport http agent-vision \
  <url>/_agent-native/mcp \
  --header "Authorization: Bearer <token>"
```

**OAuth-capable clients (Claude web/Desktop, Cursor, ChatGPT):** add just
`<url>/_agent-native/mcp` (no header) and approve the connector in the client's
sign-in popup — no token needed.

**Raw-HTTP agents (no MCP client):** every tool is also a plain HTTP endpoint at
`<url>/_agent-native/actions/<name>`, and the **same bearer token works there**.
Send `Authorization: Bearer <token>` on every request. Reads are GET with query
params; writes are POST with a JSON body. Without the header these routes return
`401 {"error":"Unauthorized"}`.

## First contact (5-line recipe)

```
1. list-projects                         → discover/confirm the workspace
2. create-diagram { title, spec }        → returns { url, svgUrl, pngUrl, warnings }
3. fetch pngUrl                          → LOOK at the render; read warnings
4. update-diagram { diagram, ops:[...] } → fix warnings (repeat 3–4 as needed)
5. share url                             → send the /d/<slug> link to the user
```

- **Never share a diagram you haven't rendered and looked at, or one with
  outstanding warnings** — warnings are a todo list, not decoration.
- The share `url` (`<app-url>/d/<slug>`) is public and needs no token; that is
  the link you hand the user. `.svg` / `.png` variants are the raw images.
- For anything beyond this loop — the spec shape, node/edge/group fields, ops
  patches, icon names, idioms (callouts, zones, trunk edges, code text) — read
  `<app-url>/skill.md`, which is the single source of truth and stays current
  with the deployed app.


