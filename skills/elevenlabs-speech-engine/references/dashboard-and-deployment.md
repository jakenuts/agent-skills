# Dashboard, auth, and deployment

Speech Engine is half code, half dashboard config. This file covers the
configuration side: creating engines and agents, wiring them together,
public vs private auth, local development with tunnels, and production
deployment shape.

## Contents
- [Engines vs agents: which ID goes where](#engines-vs-agents-which-id-goes-where)
- [Creating the Speech Engine in the dashboard](#creating-the-speech-engine-in-the-dashboard)
- [Public vs private agents](#public-vs-private-agents)
- [Signed URLs vs conversation tokens](#signed-urls-vs-conversation-tokens)
- [Local development with tunnels](#local-development-with-tunnels)
- [Production deployment shape](#production-deployment-shape)
- [Environment variables](#environment-variables)
- [Cost and limit awareness](#cost-and-limit-awareness)

## Engines vs agents: which ID goes where

You'll juggle two ID types. Confusing them is the most common
"why doesn't this connect?" outcome.

| ID | Format | Lives where | Used by |
|----|--------|-------------|---------|
| Engine ID | `seng_*` | Speech Engine config in dashboard | **Your server** — `attach(engineId, ...)`, `Server({ engineId })`, `speech_engine.get(engineId)` |
| Agent ID | `agent_*` | Agent config in dashboard | **The client** — `startSession({ agentId })`, signed-URL generation `getSignedUrl({ agentId })` |

The engine and the agent are linked in the dashboard — the agent is
configured to route through this specific Speech Engine. One engine can
back many agents (e.g., a multi-tenant deployment with per-tenant agents
all using the same custom LLM server).

## Creating the Speech Engine in the dashboard

1. ElevenLabs dashboard → **Speech Engine** (or "Voice Engine" /
   "Agents Platform → Speech Engine" depending on the current navigation)
2. **Create new engine** → assign a name
3. Set **Server URL** to your WebSocket endpoint. Format:
   - Production: `wss://api.yourcompany.com/api/speech-engine/ws`
   - Local dev: `wss://abc123.ngrok.app/api/speech-engine/ws`
   - Standalone server mode: `wss://api.yourcompany.com:3001`
4. Note the engine ID (`seng_*`) — this goes into your server code
5. Create or pick an **Agent** that will use this engine. In the
   agent's settings, choose this Speech Engine. Note the agent ID
   (`agent_*`) — this is what the client connects with
6. Configure on the agent:
   - **Voice**: pick from the voice library (or your cloned voices) and
     a TTS model. Default `eleven_flash_v2_5` for real-time.
   - **Conversation flow**: turn eagerness (Eager / Normal / Patient),
     turn timeout (1–30 s)
   - **Language**: primary + auto-detect if multilingual
   - **Overrides** (optional): enable specific fields the client is
     allowed to override at session start (prompt, firstMessage,
     language, voice, etc.). Default is "none allowed" for safety
   - **Tools** (optional): server tools, client tools, system tools
   - **Auth**: public vs private (see below)

## Public vs private agents

| | Public | Private |
|--|--------|---------|
| Client connects with | `agentId` directly | `signedUrl` (WS) or `conversationToken` (WebRTC) |
| Anyone with the agent ID can connect | yes | no |
| API key exposed to browser | no | no |
| Use for | demos, marketing widget, internal tools | anything production |

Public agents are appropriate for the embeddable widget on a marketing
site. **Anything where you'd care if a stranger ran up your bill** must
be private. The default is private — only flip it after deliberate
review.

## Signed URLs vs conversation tokens

Two flavors of short-lived credential, both with 15-minute validity.
Difference is the transport they unlock.

| | Signed URL | Conversation Token |
|--|-----------|-------------------|
| Transport | WebSocket | WebRTC |
| Generate with (TS) | `elevenlabs.conversationalAi.conversations.getSignedUrl({ agentId })` | `elevenlabs.conversationalAi.conversations.getWebrtcToken({ agentId })` |
| Generate with (Py) | `elevenlabs.conversational_ai.conversations.get_signed_url(agent_id=...)` | `elevenlabs.conversational_ai.conversations.get_webrtc_token(agent_id=...)` |
| Client option | `startSession({ signedUrl })` | `startSession({ conversationToken })` |
| Lower latency | no | yes |
| Required for React Native | no — won't work | yes |

Use conversation tokens (WebRTC) whenever you can. Use signed URLs
(WebSocket) for compatibility fallback or when WebRTC is blocked by
network policy.

15-min validity means:

- The client must **call `startSession` within 15 minutes** of
  generation. The session itself can then run as long as it likes.
- Don't pre-generate tokens and cache them server-side beyond 15 min.
- Don't ship them to the client at page load if the user might not
  start the session for a while — generate on click.

Example generation endpoint:

```ts
app.get("/api/voice/signed-url", async (_req, res) => {
  const url = await elevenlabs.conversationalAi.conversations.getSignedUrl({
    agentId: process.env.ELEVENLABS_AGENT_ID!,
  });
  res.json({ signedUrl: url });
});
```

Add your own user-auth check before generating — anyone who can hit
this endpoint can talk to your agent on your dime.

## Local development with tunnels

ElevenLabs reaches INTO your server. `localhost` is not reachable from
their cloud. You need a public tunnel for dev:

| Tool | Command | Notes |
|------|---------|-------|
| ngrok | `ngrok http 3000` | Easiest. Free tier rotates URLs on restart |
| Cloudflare Tunnel | `cloudflared tunnel --url http://localhost:3000` | Stable named tunnels available |
| Tailscale Funnel | `tailscale funnel 3000` | If you're on Tailscale already |
| localtunnel | `lt --port 3000` | OSS alternative |

Flow:

1. Run `ngrok http 3000` → get `https://abc123.ngrok.app`
2. Dashboard → Speech Engine → Server URL → `wss://abc123.ngrok.app/api/speech-engine/ws`
3. Run your server locally on port 3000
4. Start a session from the client. ElevenLabs hits the tunnel, the
   tunnel forwards to localhost, your `onTranscript` fires

If you restart ngrok and get a new URL, **update the dashboard** — the
SDK has no automatic re-registration.

ngrok also surfaces inbound requests in its web UI (`http://localhost:4040`),
which is invaluable for debugging the WebSocket upgrade handshake when
something's wrong with auth headers or paths.

## Production deployment shape

Speech Engine server **cannot run on serverless** (Vercel functions,
AWS Lambda, Cloudflare Workers' free tier) — WebSocket connections live
longer than function timeouts. Options that work:

| Host | Notes |
|------|-------|
| Fly.io | Easy WS support, regional deploys, good fit |
| Railway / Render | Long-running container, simple |
| AWS ECS / Fargate | Production-grade, regional control |
| GCP Cloud Run | Supports WS as of 2024; check timeout settings (default 60min) |
| Self-hosted VM / k8s | Total control |
| Cloudflare Workers Durable Objects | Works, but verify Speech Engine SDK compatibility per release |

Split the deployment if you want:

- **Speech Engine server**: long-lived Node/Python container, single
  region close to ElevenLabs' closest POP (US-east is a safe default)
- **Signed-URL endpoint**: can stay on your existing serverless stack
  (Vercel, Lambda), since it's a short HTTP request

Health checks: bind a simple `GET /healthz` to the same process so your
load balancer can verify the container is up. The Speech Engine WS path
won't respond to plain HTTP GETs.

Scaling: each conversation holds one WebSocket on your server. Memory is
the limit, not CPU (LLM work happens elsewhere). 1 vCPU / 1 GB RAM
comfortably holds hundreds of concurrent conversations if your LLM calls
are streamed and not buffered.

## Environment variables

| Variable | Used by | Required |
|----------|---------|----------|
| `ELEVENLABS_API_KEY` | Server SDK auth + signed URL generation + auto-verifies inbound `X-Elevenlabs-Speech-Engine-Authorization` | Yes |
| `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` / etc. | Your LLM SDK of choice | If you use one |
| `ELEVENLABS_AGENT_ID` | Convenience for your signed-URL endpoint | Recommended |
| `ELEVENLABS_ENGINE_ID` | Convenience to avoid hardcoding `seng_*` | Recommended |

Never expose `ELEVENLABS_API_KEY` to client-side code — it grants full
account access. In Next.js, this means: not in `NEXT_PUBLIC_*` vars, not
in any file imported from `app/` or `pages/` components.

## Cost and limit awareness

Speech Engine pricing has two components billed separately:

1. **ElevenLabs minutes**: STT + TTS + orchestration, billed per minute
   of conversation
2. **Your LLM**: whatever OpenAI / Anthropic / Gemini / self-hosted
   costs

Common cost surprises:

- Forgetting to pass the abort signal → LLM keeps generating after the
  user interrupts; you pay for tokens the user never heard
- Verbose system prompts → larger input token cost on every turn,
  including ignored interruption turns
- High-quality TTS model on chat-style use case → 2–5× the cost of Flash
  for marginal perceived quality gain
- Public agents with no rate limiting → bills from bots / abuse

Set up usage alerts in the ElevenLabs dashboard. Per-agent and
per-conversation usage data is available via the conversations API for
your own dashboards.
