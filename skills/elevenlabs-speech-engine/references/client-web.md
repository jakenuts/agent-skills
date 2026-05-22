# Client — Web (React + vanilla JS)

The browser doesn't talk to your Speech Engine server directly. It opens
a WebRTC (or WebSocket fallback) audio session with ElevenLabs using an
**agent ID** (public) or a **signed URL / conversation token** (private).
ElevenLabs handles the audio and reaches into your server over its own
WebSocket connection.

## Contents
- [Packages](#packages)
- [React: ConversationProvider + granular hooks](#react-conversationprovider--granular-hooks)
- [Vanilla TypeScript: `Conversation.startSession`](#vanilla-typescript-conversationstartsession)
- [Connection options](#connection-options)
- [Granular hooks reference](#granular-hooks-reference)
- [Callbacks](#callbacks)
- [Client tools](#client-tools)
- [The embeddable widget](#the-embeddable-widget)

## Packages

| Package | Use for |
|---------|---------|
| `@elevenlabs/react` | React / Next.js apps |
| `@elevenlabs/client` | Vanilla TS/JS, Vue, Svelte, framework-agnostic |
| `@elevenlabs/react-native` | iOS / Android — see [client-mobile.md](client-mobile.md) |
| `@elevenlabs/convai-widget-embed` | Drop-in `<elevenlabs-convai>` web component |

`@elevenlabs/react` re-exports everything from `@elevenlabs/client` — no
need to install both.

## React: ConversationProvider + granular hooks

The recommended modern pattern. `ConversationProvider` is the context;
small hooks subscribe to slices so re-renders are scoped.

```tsx
import {
  ConversationProvider,
  useConversationControls,
  useConversationStatus,
  useConversationMode,
  useConversationInput,
} from "@elevenlabs/react";

function App() {
  return (
    <ConversationProvider>
      <VoiceUI />
    </ConversationProvider>
  );
}

function VoiceUI() {
  const { startSession, endSession, sendUserMessage, sendContextualUpdate } = useConversationControls();
  const { status } = useConversationStatus();                  // 'disconnected' | 'connecting' | 'connected' | 'disconnecting'
  const { isSpeaking, isListening, mode } = useConversationMode();
  const { isMuted, setMuted } = useConversationInput();

  const start = async () => {
    const { signedUrl } = await fetch("/api/voice/signed-url").then(r => r.json());
    startSession({
      signedUrl,
      onConnect: ({ conversationId }) => console.log("connected:", conversationId),
      onError: (msg) => console.error(msg),
      onMessage: ({ role, message }) => console.log(role, message), // 'user' | 'agent'
    });
  };

  return (
    <div>
      <p>Status: {status}</p>
      <p>{isSpeaking ? "Agent speaking" : isListening ? "Listening" : "Idle"}</p>
      <button onClick={start} disabled={status !== "disconnected"}>Talk</button>
      <button onClick={() => endSession()} disabled={status === "disconnected"}>Stop</button>
      <button onClick={() => setMuted(!isMuted)}>{isMuted ? "Unmute" : "Mute"} mic</button>
    </div>
  );
}
```

`ConversationProvider` must wrap every component that calls a conversation
hook. Hooks throw at render if used outside it.

`ConversationProvider` also accepts session-config props directly — useful
when the agent ID is static and you want callbacks registered once at the
provider level:

```tsx
<ConversationProvider
  agentId="agent_abc"
  onConnect={({ conversationId }) => analytics.track("voice_start", { conversationId })}
  onError={(msg) => Sentry.captureMessage(msg)}
>
  <VoiceUI />
</ConversationProvider>
```

Note: `@elevenlabs/react` also re-exports `useScribe` (a hook for the
ElevenLabs Scribe real-time STT product). That is **not** part of Speech
Engine — it's a separate product for getting raw transcripts without an
agent. Don't confuse them.

### Convenience hook: `useConversation`

Combines all granular hooks. Less performant (every state change in any
sub-context re-renders the consuming component) but quicker to write for
small UIs. Also lets you pass session config / callbacks at the hook
level as defaults for `startSession()`:

```tsx
import { useConversation } from "@elevenlabs/react";

function VoiceUI() {
  const conv = useConversation({
    onConnect: ({ conversationId }) => console.log(conversationId),
    onMessage: ({ role, message }) => console.log(role, message),
    micMuted: false,
    volume: 0.8,

    // session config options also accepted here as defaults for startSession()
    dynamicVariables: { user_name: "Alice", tier: "premium" }, // injected into prompt
    userId: "user_42",                                          // for analytics / conversation grouping
    clientTools: { /* see below */ },
    customLlmExtraBody: { reasoning_effort: "high" },           // forwarded to your custom LLM
    textOnly: false,                                            // true = text-only mode, no audio
    useWakeLock: true,                                          // keep screen awake during session
    connectionDelay: { android: 3000 },                         // delay before connect on slower devices
  });

  // conv.startSession({ signedUrl }) uses the above callbacks/config as defaults
  // conv.startSession({ signedUrl, onMessage: x }) overrides per-session
  // conv.status, conv.isSpeaking, conv.isListening, conv.isMuted, conv.setMuted, ...
}
```

Hook-level callbacks are ref-stable across renders. Callbacks passed
directly to `startSession()` are one-shot per session and can capture
render-local state.

## Vanilla TypeScript: `Conversation.startSession`

```ts
import { Conversation } from "@elevenlabs/client";

const conversation = await Conversation.startSession({
  signedUrl,                                       // for private agents
  // OR: agentId: "agent_abc"                      // for public agents

  onConnect: ({ conversationId }) => { /* ... */ },
  onDisconnect: (details) => { /* details.reason: 'error' | 'agent' | 'user' */ },
  onMessage: ({ role, message }) => { /* role: 'user' | 'agent' */ },
  onError: (msg) => { /* ... */ },
  onModeChange: ({ mode }) => { /* 'speaking' | 'listening' */ },
  onStatusChange: ({ status }) => { /* 'connected' | 'connecting' | 'disconnecting' | 'disconnected' */ },
});

// Later
await conversation.endSession();
```

## Connection options

| Option | When to use |
|--------|-------------|
| `agentId: "agent_*"` | Public agent (no auth) — never use in production for private workloads |
| `signedUrl: string` | Private agent, WebSocket transport. Generate server-side, 15-min validity |
| `conversationToken: string` | Private agent, WebRTC transport (recommended for native + modern browsers) |
| `connectionType: 'webrtc' \| 'websocket'` | Force transport. Default: WebRTC where supported |

WebRTC has lower latency and better behavior over flaky networks.
WebSocket is the fallback. The SDK picks WebRTC by default if the
browser supports it.

Combine with overrides at session start (each field must be enabled in
the dashboard first or it's ignored):

```ts
startSession({
  signedUrl,
  overrides: {
    agent: {
      prompt: { prompt: "You are helping me practice Spanish." },
      firstMessage: "Hola, ¿cómo puedo ayudarte?",
      language: "es",
    },
    tts: { voiceId: "21m00Tcm4TlvDq8ikWAM" },
  },
});
```

## Granular hooks reference

All under `@elevenlabs/react`:

| Hook | Returns | Re-renders on |
|------|---------|---------------|
| `useConversationStatus()` | `{ status, message }` | Connection state changes |
| `useConversationMode()` | `{ mode, isSpeaking, isListening }` | Mode flips between speaking/listening |
| `useConversationInput()` | `{ isMuted, setMuted }` | Mic mute state |
| `useConversationFeedback()` | `{ canSendFeedback, sendFeedback }` | Whether thumbs-up/down is available |
| `useConversationControls()` | All control methods (start/end/send/setVolume/getId/changeInputDevice/...) | Never re-renders (refs-stable) |
| `useConversationClientTool(name, fn)` | Registers a single client tool reactively | n/a |
| `useRawConversation()` | The underlying `VoiceConversation` instance | Only on session start/end |
| `useConversation(opts)` | Everything combined | Any change in any sub-context (use sparingly) |

`useConversationControls()` returns:

```ts
{
  startSession(options?: HookOptions): void
  endSession(): void
  sendUserMessage(text: string): void
  sendMultimodalMessage(options: MultimodalMessageInput): void
  uploadFile(file: Blob): Promise<UploadFileResult>
  sendContextualUpdate(text: string, options?: ContextualUpdateOptions): void
  sendUserActivity(): void
  sendMCPToolApprovalResult(toolCallId: string, isApproved: boolean): void
  setVolume(options: { volume: number }): void
  changeInputDevice(config): Promise<void>
  changeOutputDevice(config): Promise<void>
  getInputByteFrequencyData(): Uint8Array      // 0-255, focused on 100-8000 Hz
  getOutputByteFrequencyData(): Uint8Array
  getInputVolume(): number
  getOutputVolume(): number
  getId(): string                              // conversation ID
}
```

The frequency-data and volume getters are what you draw mic/agent
visualizations from — call them inside a `requestAnimationFrame` loop.

## Callbacks

Available as `startSession({ ... })` options or via `useConversation({...})`
hook options:

| Callback | Args | Purpose |
|----------|------|---------|
| `onConnect` | `({ conversationId })` | Session opened |
| `onDisconnect` | `(details: DisconnectionDetails)` | Session ended; `details.reason` is `'error' \| 'agent' \| 'user'` |
| `onError` | `(message: string)` | Recoverable or fatal error |
| `onMessage` | `({ role: 'user' \| 'agent', source?, message: string })` | Each transcript or AI response chunk. `source` (`'user' \| 'ai'`) is also present but deprecated — prefer `role` |
| `onAudio` | `(base64Audio: string)` | Raw audio frame, base64-encoded (rarely needed) |
| `onModeChange` | `({ mode: 'speaking' \| 'listening' })` | Agent-speaks vs user-speaks |
| `onStatusChange` | `({ status: 'connected' \| 'connecting' \| 'disconnecting' \| 'disconnected' })` | Connection lifecycle |
| `onVadScore` | `({ vadScore: number })` | Voice activity detection level — useful for mic-activity indicators |
| `onInterruption` | `(event)` | Agent's reply was cut short by user speech |
| `onCanSendFeedbackChange` | `({ canSendFeedback })` | Thumbs-up/down availability per turn |
| `onAgentResponseCorrection` | `({ original_agent_response, corrected_agent_response })` | Agent reworded after speaking (rare) |
| `onAgentChatResponsePart` | `(part)` | Streaming chunk of agent text |
| `onUnhandledClientToolCall` | `(toolCall)` | Agent called a tool you didn't register |
| `onAgentToolRequest` / `onAgentToolResponse` | tool call telemetry | Observability |
| `onConversationMetadata` | metadata | Session metadata payload |
| `onMCPToolCall` / `onMCPConnectionStatus` | MCP integration | If using MCP-served tools |
| `onAsrInitiationMetadata` | metadata | Speech-to-text setup info |
| `onAudioAlignment` | alignment | Word-level audio timing (for captioning) |
| `onGuardrailTriggered` | `(event)` | Content moderation event |
| `onDebug` | `(payload)` | Verbose protocol events; enable via `debug: true` |

## Client tools

Client tools are functions the agent can call in the browser. The
function name must match a tool the agent is configured to use (in the
dashboard or via overrides).

```tsx
startSession({
  signedUrl,
  clientTools: {
    navigateTo: async ({ path }: { path: string }) => {
      router.push(path);
      return "navigated";                          // value sent back to the agent
    },
    getCartContents: async () => {
      return JSON.stringify(cart);
    },
  },
});
```

Or per-tool, reactively:

```tsx
function CartTool() {
  useConversationClientTool("getCartContents", async () => JSON.stringify(useCart().items));
  return null;
}
```

Return values get serialized and fed back to the agent as the tool's
response.

## The embeddable widget

If you don't want to write any client code, use the pre-bundled widget:

```html
<script src="https://unpkg.com/@elevenlabs/convai-widget-embed" async></script>
<elevenlabs-convai agent-id="agent_abc"></elevenlabs-convai>
```

It renders a floating chat-bubble button that opens a voice UI. Best for
demos and marketing-site sales bots; you give up most customization. For
real product surfaces, use the React or vanilla SDK.
