---
name: elevenlabs-speech-engine
description: >-
  ElevenLabs Speech Engine — the SDK for giving a voice interface to a custom
  agent you host yourself (your existing chat agent, LangGraph workflow,
  containerized LLM service, etc.). ElevenLabs runs the audio pipeline (STT,
  turn detection, VAD, TTS, barge-in); your server receives transcripts over
  a WebSocket and streams text replies back. Use when wiring an existing
  non-ElevenLabs agent to voice, when the user mentions "Speech Engine",
  `seng_*` engine IDs, `@elevenlabs/elevenlabs-js` `speechEngine.attach()` /
  `SpeechEngine.Server`, Python `AsyncElevenLabs.speech_engine`, or
  full-duplex voice with bring-your-own-LLM. Also covers the matching
  client SDKs (`@elevenlabs/client`, `@elevenlabs/react`,
  `@elevenlabs/react-native`, the convai widget) for the browser/mobile
  side. Do NOT use this skill for ElevenAgents (fully hosted agent platform
  — different product, see distinction below) or plain TTS / STT calls.
---

# ElevenLabs Speech Engine

Speech Engine is the **server-side** product that lets you keep your existing
agent (any LLM/workflow that produces text) and bolt a real-time voice
interface in front of it. ElevenLabs runs everything between the microphone
and the LLM call; you only handle "transcript in, reply text out."

```
[Browser / Mobile]            [ElevenLabs Cloud]               [Your Server]
       │                              │                              │
       │ 1. signed URL request ─────▶ │                              │
       │ ◀──── signed URL (15 min) ─  │                              │
       │ 2. WebRTC audio ──────────▶  │                              │
       │                              │ 3. STT + VAD + turn detect   │
       │                              │ 4. WS open ─────────────────▶│
       │                              │ 5. user_transcript event    │
       │                              │    + AbortSignal (TS) /      │
       │                              │    asyncio cancel (Py)       │
       │                              │                              │ 6. LLM call (stream)
       │                              │ 7. session.sendResponse() ◀──│
       │                              │ 8. TTS                       │
       │ 9. WebRTC audio ◀──────────  │                              │
       │                              │                              │
       │ — user interrupts — ───────▶ │                              │
       │                              │ 10. signal aborted /         │
       │                              │     in-flight LLM cancelled  │
       │                              │ 11. new user_transcript ────▶│
```

The SDK gives you the WebSocket server (`speechEngine.attach()`,
`SpeechEngine.Server`, Python `engine.serve()` / `engine.create_session()`)
plus client libraries (`@elevenlabs/react`, `@elevenlabs/client`,
`@elevenlabs/react-native`) for the user-facing side.

## Speech Engine vs ElevenAgents — pick the right product first

These look similar in marketing but are different runtime paths. Choosing
the wrong one means rewriting both server and dashboard config.

| You want… | Use |
|-----------|-----|
| Keep your existing agent / LLM / workflow, just add voice | **Speech Engine** (this skill) |
| ElevenLabs to host the LLM, knowledge base, tools, telephony | **ElevenAgents** (different product) |
| ElevenAgents to call your LLM endpoint for token generation only | ElevenAgents with "Custom LLM" — also different from Speech Engine |

Engine IDs are `seng_*`. Agent IDs are `agent_*`. If the user shows you an
`agent_*` ID and a server URL setting, they may actually be using
"Custom LLM" under ElevenAgents (an OpenAI-compatible endpoint contract)
rather than Speech Engine (which uses a WebSocket protocol that the SDK
implements for you). Confirm before writing code — the two are not
interchangeable.

## The four moving parts

1. **Server (this is your code)** — a WebSocket endpoint that receives
   transcripts and streams text back. Node or Python SDK does the protocol.
2. **Dashboard config** — create a Speech Engine in the ElevenLabs dashboard,
   note its `seng_*` ID, set the server URL it should connect to, pick the
   voice and TTS model.
3. **Client (browser/mobile)** — uses `@elevenlabs/react`, `@elevenlabs/client`,
   or `@elevenlabs/react-native` to open a WebRTC audio session against
   ElevenLabs (not against your server directly).
4. **Auth bridge** — your server generates short-lived **signed URLs** so the
   client can connect without ever seeing your `ELEVENLABS_API_KEY`.

Skip any reference below that doesn't match the current task — every file
is loadable on its own.

| Reference | Load when… |
|-----------|-----------|
| [references/server-typescript.md](references/server-typescript.md) | Writing the Node server (`speechEngine.attach`, `SpeechEngine.Server`, OpenAI/Anthropic/Gemini stream forwarding, AbortSignal interrupt handling, Express/Fastify/Next.js integration) |
| [references/server-python.md](references/server-python.md) | Writing the Python server (`AsyncElevenLabs.speech_engine`, `engine.serve()`, FastAPI/Starlette `engine.create_session()`, `asyncio.CancelledError` interrupt handling, `SpeechEngineServer`) |
| [references/client-web.md](references/client-web.md) | Building the browser UI (`ConversationProvider`, granular hooks, `Conversation.startSession`, signed-URL flow, public vs private agents, audio device controls, frequency-data visualizations) |
| [references/client-mobile.md](references/client-mobile.md) | React Native — LiveKit peer deps, iOS `NSMicrophoneUsageDescription`, Android `RECORD_AUDIO`, Expo dev build requirement |
| [references/full-duplex.md](references/full-duplex.md) | Tuning the conversational feel — barge-in/interruption handling, turn eagerness (Eager/Normal/Patient), turn timeout, what is and isn't configurable, latency optimization (Flash/Turbo model picks, regional co-location, sub-second targets) |
| [references/ui-patterns.md](references/ui-patterns.md) | Building the conversational UI — status/mode indicators, mic visualization, transcript rendering, `sendUserMessage` / `sendContextualUpdate`, conversation overrides, client tools, the embeddable widget |
| [references/dashboard-and-deployment.md](references/dashboard-and-deployment.md) | Dashboard setup, voice/model selection, local dev with ngrok, production deployment, public vs private agent auth, signed URL generation |

## Minimum viable conversation

**Server (TypeScript, attach to Express):**

```ts
import express from "express";
import { createServer } from "http";
import { ElevenLabsClient } from "@elevenlabs/elevenlabs-js";
import OpenAI from "openai";

const app = express();
const httpServer = createServer(app);

const elevenlabs = new ElevenLabsClient({ apiKey: process.env.ELEVENLABS_API_KEY });
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

// 1. Speech Engine WS endpoint — ElevenLabs connects in here per conversation
//    attach() is synchronous; it returns a handle, not a Promise.
elevenlabs.speechEngine.attach("seng_123", httpServer, "/api/speech-engine/ws", {
  async onTranscript(transcript, signal, session) {
    const stream = await openai.responses.create(
      {
        model: "gpt-4o",
        input: transcript.map(m => ({
          role: m.role === "agent" ? "assistant" : m.role,  // <-- role mapping
          content: m.content,
        })),
        stream: true,
      },
      { signal },                                            // <-- barge-in cancels LLM
    );
    session.sendResponse(stream);                            // SDK extracts text
  },
});

// 2. Signed-URL endpoint — client calls this to get a 15-min token
app.get("/api/voice/signed-url", async (_req, res) => {
  const url = await elevenlabs.conversationalAi.conversations.getSignedUrl({
    agentId: "agent_abc",
  });
  res.json({ signedUrl: url });
});

httpServer.listen(3000);
```

**Client (React):**

```tsx
import { ConversationProvider, useConversationControls, useConversationStatus, useConversationMode } from "@elevenlabs/react";

function App() {
  return (
    <ConversationProvider>
      <VoiceUI />
    </ConversationProvider>
  );
}

function VoiceUI() {
  const { startSession, endSession } = useConversationControls();
  const { status } = useConversationStatus();
  const { isSpeaking } = useConversationMode();

  const start = async () => {
    const { signedUrl } = await fetch("/api/voice/signed-url").then(r => r.json());
    startSession({ signedUrl });
  };

  return (
    <>
      <p>Status: {status} {isSpeaking && "(agent speaking)"}</p>
      <button onClick={start}>Talk</button>
      <button onClick={() => endSession()}>Stop</button>
    </>
  );
}
```

That's a full-duplex voice loop in front of your existing agent. The
`signal` is the only thing wired in for barge-in — the SDK does the rest.

## Critical conventions and gotchas

Trip-wires for an agent who hasn't used Speech Engine before. Skim before
writing code.

- **`transcript[i].role` is `'user' | 'agent'`, not `'user' | 'assistant'`.**
  OpenAI/Anthropic/Gemini expect `'assistant'`. Map `agent → assistant` when
  you forward the history, or the model will see a malformed conversation
  and answer worse.
- **In TypeScript, you MUST pass `{ signal }` to the LLM SDK call.** Without
  it, barge-in only stops audio playback — the LLM keeps generating, you keep
  paying tokens, and the next turn fights stale context. OpenAI, Anthropic,
  and Vercel `ai` SDK all accept an `AbortSignal` option.
- **In Python, barge-in raises `asyncio.CancelledError` inside your handler.**
  Let it propagate. Don't wrap `await session.send_response(...)` in
  `try/except Exception` that swallows cancellation, or you'll leak in-flight
  LLM requests.
- **Never put your `ELEVENLABS_API_KEY` in client code.** The browser asks
  your server for a `signedUrl` (WebSocket) or `conversationToken` (WebRTC).
  Tokens are valid for 15 minutes — the **session** can run longer, but the
  initial connect must happen inside that window.
- **`session.sendResponse()` auto-detects OpenAI / Anthropic / Gemini
  streams.** You can pass the raw `await openai.responses.create({ stream: true })`
  result directly — no manual extraction. Strings and arbitrary async
  iterables of strings also work.
- **The server's WebSocket auth header (`X-Elevenlabs-Speech-Engine-Authorization`)
  is verified automatically** by both `attach()` and `SpeechEngine.Server`,
  using `apiKey` from options or `ELEVENLABS_API_KEY` env. Don't add your
  own auth on the path — you'll fight the SDK.
- **VAD thresholds, interrupt eagerness, silence detection are NOT
  per-conversation API knobs.** They live in the dashboard ("Conversation
  flow" → turn eagerness Eager/Normal/Patient, turn timeout 1–30s). If a
  reviewer asks "tune the interrupt sensitivity," that's a dashboard change,
  not code.
- **React Native requires Expo dev build, not Expo Go.** WebRTC needs native
  modules (`@livekit/react-native`, `@livekit/react-native-webrtc`). Tell the
  user up front if they're on Expo Go — they need to switch.
- **`ConversationProvider` is mandatory before any conversation hook.**
  Calling `useConversationControls()` outside it throws at render. Wrap at
  the app root or the smallest subtree that contains the voice UI.
- **Prefer the granular hooks for performance.** `useConversation()` (the
  combined hook) re-renders on every state change in any sub-context.
  `useConversationStatus`, `useConversationMode`, `useConversationInput`,
  `useConversationFeedback` each subscribe to only their slice — use them
  in leaf components.
- **`Status` has four values**, not three: `'disconnected' | 'connecting' | 'connected' | 'disconnecting'`. Don't forget `'disconnecting'`
  when rendering connection state — typically render it like `'connecting'`
  (spinner) but with a "hanging up" label.
- **`onAudio` payload is base64-encoded text**, not a `Uint8Array`. If you
  need bytes, decode it: `Uint8Array.from(atob(base64Audio), c => c.charCodeAt(0))`.
  Most apps don't need this — audio playback is handled by the SDK.
- **The token method is `getWebrtcToken` (TS) / `get_webrtc_token` (Py)**,
  but the client-side option you pass into `startSession` is still spelled
  `conversationToken`. Old docs and tutorials may say
  `getConversationToken` — that name no longer exists.
- **Local dev needs a tunnel.** ElevenLabs connects INTO your server, so
  `localhost:3000` is not reachable. `ngrok http 3000` (or Cloudflare Tunnel,
  Tailscale Funnel, etc.); paste the public URL into the Speech Engine's
  server URL field in the dashboard. The tunnel must stay up for the
  duration of testing.
- **Voice/model picks dominate latency.** `eleven_flash_v2_5` gives ~135 ms
  end-to-end first-byte audio; `eleven_multilingual_v2` is higher quality
  but slower. Default to Flash for chat/assistant feel, Multilingual v2
  only when audio quality is non-negotiable. See
  [full-duplex.md](references/full-duplex.md).
- **`sendContextualUpdate(text)` vs `sendUserMessage(text)`** —
  contextual updates are background info the agent receives but does not
  reply to (e.g., "user just navigated to checkout"). User messages prompt
  a reply (e.g., a typed message in a chat fallback). Don't confuse them
  or the agent will start narrating page navigations.

## Diagnostics first

When voice "doesn't work", check in this order:

1. **Does your server's WS receive `init` then `user_transcript`?** Add
   `onInit` and a log in `onTranscript`. No `init` = ElevenLabs can't reach
   your URL (tunnel down, wrong path, or auth header rejected). No
   `user_transcript` = client never connected (signed URL expired? wrong
   agent ID? mic permission denied?).
2. **Does `session.sendResponse(stream)` see anything?** Log
   `for await (const chunk of stream)` once before passing — confirms the
   LLM is actually streaming.
3. **Browser DevTools → Console** for `onError` / `onDebug` output. The
   client SDK surfaces auth, network, and audio errors there. Use
   `debug: true` in the React hook options. Inspect
   `onDisconnect(details)` — `details.reason` is `'error' | 'agent' | 'user'`
   and tells you who closed (the agent server-side, the user clicking End,
   or a fatal error).
4. **`onVadScore`** callback — if it's never firing, the mic isn't capturing.
   Check `getUserMedia` permission and `changeInputDevice()` selection.
5. **`onModeChange`** — confirms the agent is transitioning
   `listening → speaking → listening`. If stuck in `listening`, your server
   isn't returning a response.

## Picking the right next reference

- "Write the server" → `server-typescript.md` or `server-python.md`
- "Build the browser UI" → `client-web.md`
- "Build the mobile app" → `client-mobile.md`
- "Conversation feels laggy / agent talks over me / interrupts me too eagerly"
  → `full-duplex.md`
- "Need transcript bubbles, mic indicator, send a typed message, push
  background context" → `ui-patterns.md`
- "Where do I configure the engine / signed URLs / ngrok / production
  deploy" → `dashboard-and-deployment.md`
