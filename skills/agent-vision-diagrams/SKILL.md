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

## Connecting (given the user's `{ url, token }`)

The user does a ~30s one-time setup: log into their Agent Vision app, open
`<url>/_agent-native/mcp/connect`, mint a connection token, and paste the **app
URL + token** to you. The token is per-user, scoped, expiry-bound, and revocable
from that same page. It never exposes their password or any server secret.

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

