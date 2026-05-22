# Server — TypeScript / Node

`@elevenlabs/elevenlabs-js` ships the Speech Engine server. ElevenLabs
opens a WebSocket connection **to** your server per conversation, sends
`user_transcript` events, and your code streams text back via
`session.sendResponse()`.

## Contents
- [Install and import](#install-and-import)
- [Two ways to mount the server](#two-ways-to-mount-the-server)
- [Callbacks](#callbacks)
- [Forwarding LLM streams](#forwarding-llm-streams)
- [Interruption (AbortSignal) handling](#interruption-abortsignal-handling)
- [Auth and the X-Elevenlabs-Speech-Engine-Authorization header](#auth-and-the-x-elevenlabs-speech-engine-authorization-header)
- [Framework integrations](#framework-integrations)
- [Generating signed URLs for the client](#generating-signed-urls-for-the-client)

## Install and import

```bash
npm install @elevenlabs/elevenlabs-js
```

```ts
import { ElevenLabsClient, SpeechEngine } from "@elevenlabs/elevenlabs-js";
```

Runtime support: Node 15+, Vercel, Cloudflare Workers, Deno v1.25+,
Bun 1.0+. The SDK uses the global `fetch` if available, otherwise
`node-fetch`.

## Two ways to mount the server

### A. Attach to an existing HTTP server

Use when you already have Express / Fastify / Next.js / `http.createServer`
and want Speech Engine on a path next to your other routes.

```ts
import express from "express";
import { createServer } from "http";
import { ElevenLabsClient } from "@elevenlabs/elevenlabs-js";

const app = express();
const httpServer = createServer(app);
const elevenlabs = new ElevenLabsClient({ apiKey: process.env.ELEVENLABS_API_KEY });

// attach() is synchronous — returns a SpeechEngineAttachment handle, not a Promise.
elevenlabs.speechEngine.attach(
  "seng_123",                          // engine ID from the dashboard
  httpServer,                          // raw Node http.Server
  "/api/speech-engine/ws",             // path the dashboard's "Server URL" points to
  {
    debug: true,
    onInit(conversationId, session) { /* ... */ },
    async onTranscript(transcript, signal, session) { /* ... */ },
    onClose(session) { /* ... */ },
    onDisconnect(session) { /* ... */ },
    onError(error, session) { /* ... */ },
  },
);

httpServer.listen(3000);
```

Configure the dashboard's server URL to your tunnel + path, e.g.
`wss://abc123.ngrok.app/api/speech-engine/ws`.

### B. Standalone WebSocket server

Use when Speech Engine is the only thing this process handles.

```ts
import { SpeechEngine } from "@elevenlabs/elevenlabs-js";

const server = new SpeechEngine.Server({
  port: 3001,
  engineId: "seng_123",
  apiKey: process.env.ELEVENLABS_API_KEY,
  async onTranscript(transcript, signal, session) {
    const reply = await myAgent.run(transcript, { signal });
    session.sendResponse(reply);
  },
});

server.start();
```

Dashboard server URL points at the host:port directly,
`wss://myserver.com:3001`.

## Callbacks

Both `attach()` and `Server` take the same callback set. All are optional
except `onTranscript`.

| Callback | Fires when | Args |
|----------|-----------|------|
| `onInit` | Session opened (one per conversation) | `(conversationId: string, session: Session)` |
| `onTranscript` | User just spoke and was transcribed | `(transcript: TranscriptMessage[], signal: AbortSignal, session: Session)` |
| `onClose` | Clean disconnect by ElevenLabs | `(session: Session)` |
| `onDisconnect` | Unexpected WS drop | `(session: Session)` |
| `onError` | Protocol or transport error | `(error: Error, session: Session)` |

`Message` is `{ role: 'user' | 'agent', content: string }`. The full
conversation history is sent every time — you do not need to maintain it.

`Session` exposes:

- `session.sendResponse(stringOrStreamOrIterable)` — stream text back
- `session.conversationId` — same ID as `onInit`

## Forwarding LLM streams

`sendResponse()` is overloaded: pass a string, a native LLM stream object,
or any `AsyncIterable<string>`. Text extraction for OpenAI, Anthropic, and
Gemini is automatic.

```ts
// Plain string
session.sendResponse("Hello there.");

// OpenAI responses stream
const stream = await openai.responses.create(
  { model: "gpt-4o", input: [...], stream: true },
  { signal },
);
session.sendResponse(stream);

// OpenAI chat completions stream
const stream = await openai.chat.completions.create(
  { model: "gpt-4o-mini", messages: [...], stream: true },
  { signal },
);
session.sendResponse(stream);

// Anthropic
const stream = anthropic.messages.stream(
  { model: "claude-sonnet-4-6", messages: [...] },
  { signal },                                    // pass signal at the request level
);
session.sendResponse(stream);

// Google Gemini
const stream = await gemini.generateContentStream({ ... });
session.sendResponse(stream);

// Anything custom
async function* generator() {
  yield "Hello ";
  yield "world.";
}
session.sendResponse(generator());
```

Map `transcript[i].role === 'agent'` to `'assistant'` before passing to
OpenAI/Anthropic/Gemini — they reject `'agent'`:

```ts
input: transcript.map(m => ({
  role: m.role === "agent" ? "assistant" : m.role,
  content: m.content,
}))
```

## Interruption (AbortSignal) handling

`onTranscript` receives an `AbortSignal` that fires the moment the user
starts speaking again. **You must pass it to your LLM call** or the SDK
can only stop audio playback — the model keeps generating.

```ts
async onTranscript(transcript, signal, session) {
  const stream = await openai.responses.create(
    { model: "gpt-4o", input: [...], stream: true },
    { signal },                                    // ← critical
  );
  session.sendResponse(stream);
}
```

If you do background work between the transcript and the LLM call (RAG
lookup, tool resolution, DB fetch), pass `signal` to those too — or check
`signal.aborted` between steps:

```ts
async onTranscript(transcript, signal, session) {
  const context = await db.query(transcript[transcript.length - 1].content, { signal });
  if (signal.aborted) return;                      // user already moved on
  const stream = await openai.responses.create({ ... }, { signal });
  session.sendResponse(stream);
}
```

Aborting is "let it throw" — the `AbortError` will propagate out of the
LLM SDK call. Don't `try/catch` it back to success.

## Auth and the X-Elevenlabs-Speech-Engine-Authorization header

Every incoming connection carries
`X-Elevenlabs-Speech-Engine-Authorization`. Both `attach()` and `Server`
verify it automatically using `apiKey` (option) or `ELEVENLABS_API_KEY`
(env var). Reject reasons surface in `onError`.

Do NOT add your own middleware that strips or rewrites this header on
the Speech Engine path. If you have a global auth middleware, exempt the
path:

```ts
app.use("/api", myAuth);                           // applies elsewhere
// /api/speech-engine/ws is handled by elevenlabs.speechEngine.attach()
// at the http.Server level, below Express — your middleware never sees it
```

The WebSocket upgrade is intercepted before Express routes run, so this
just works.

## Framework integrations

| Framework | Pattern |
|-----------|---------|
| Express | `attach(engineId, httpServer, path, callbacks)` against the underlying `http.Server` from `createServer(app)` |
| Fastify | `attach(engineId, fastify.server, path, callbacks)` — `.server` exposes the underlying Node server |
| Next.js (custom server) | `attach(engineId, server, path, callbacks)` in the custom `server.js`; on Vercel use a standalone deployment (see below) |
| Cloudflare Workers / Edge | Use Durable Objects with WebSocket upgrade; `SpeechEngine.Server` may not be supported on edge runtimes — confirm latest SDK release notes |
| Plain Node | `const server = http.createServer(); attach(engineId, server, "/", cb); server.listen(3001)` |

**Vercel / serverless**: long-lived WebSocket connections don't fit
serverless function timeouts. Run Speech Engine on a separate Node host
(Fly, Railway, Render, a VM, or an ECS service) and point the dashboard
there. The signed-URL endpoint can still live on Vercel.

## Generating signed URLs for the client

The browser/mobile client never holds your API key. Your server exchanges
the key for a 15-minute signed URL the client uses to connect:

```ts
app.get("/api/voice/signed-url", async (_req, res) => {
  const url = await elevenlabs.conversationalAi.conversations.getSignedUrl({
    agentId: "agent_abc",                          // the agent wired to your Speech Engine
  });
  res.json({ signedUrl: url });
});
```

For WebRTC (preferred for native apps and modern browsers), use a
WebRTC token instead:

```ts
const token = await elevenlabs.conversationalAi.conversations.getWebrtcToken({
  agentId: "agent_abc",
});
res.json({ conversationToken: token });
```

Note: the SDK method is `getWebrtcToken`, but the client option you pass
into `startSession()` is still spelled `conversationToken`.

Both expire in 15 minutes; the session itself can run longer once
established. See [client-web.md](client-web.md) for how the client uses
them and [dashboard-and-deployment.md](dashboard-and-deployment.md) for
the public-vs-private agent distinction.
