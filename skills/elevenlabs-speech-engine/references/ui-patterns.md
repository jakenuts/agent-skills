# UI patterns — building the conversational interface

The SDK gives you state + control + raw audio data; you decide what to
render. This file collects the patterns that consistently work: status
indicators, mic visualizations, transcript bubbles, typed-message
fallback, and contextual updates from the UI to the agent.

## Contents
- [Status and mode display](#status-and-mode-display)
- [Mic and agent audio visualizations](#mic-and-agent-audio-visualizations)
- [Transcript rendering](#transcript-rendering)
- [Typed-message fallback (`sendUserMessage`)](#typed-message-fallback-senduserMessage)
- [Background context (`sendContextualUpdate`)](#background-context-sendcontextualupdate)
- [Conversation overrides at start](#conversation-overrides-at-start)
- [Client tools (UI-triggered actions)](#client-tools-ui-triggered-actions)
- [Feedback thumbs](#feedback-thumbs)
- [Device pickers](#device-pickers)

## Status and mode display

Two orthogonal pieces of state:

- **Status** (`useConversationStatus`): `'disconnected' | 'connecting' | 'connected' | 'disconnecting'`
- **Mode** (`useConversationMode`): `'speaking' | 'listening'` plus
  `isSpeaking` / `isListening` booleans

Patterns:

```tsx
function StatusBadge() {
  const { status } = useConversationStatus();
  const { isSpeaking } = useConversationMode();

  if (status === "disconnected") return <Badge variant="grey">Idle</Badge>;
  if (status === "connecting") return <Badge variant="yellow">Connecting…</Badge>;
  if (status === "disconnecting") return <Badge variant="yellow">Hanging up…</Badge>;
  return (
    <Badge variant={isSpeaking ? "purple" : "green"}>
      {isSpeaking ? "Speaking" : "Listening"}
    </Badge>
  );
}
```

Don't conflate the two. The connection can be `connected` and the agent
neither speaking nor listening for a brief moment (e.g., the LLM is
still generating). Use `isSpeaking` for the "the agent is making noise"
indicator and `isListening` for the mic-hot indicator.

## Mic and agent audio visualizations

`useConversationControls()` exposes raw frequency-data getters that
return `Uint8Array` (0–255) focused on the 100–8000 Hz range — exactly
what you want for voice. Read them inside `requestAnimationFrame`:

```tsx
function MicVisualizer() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const { getInputByteFrequencyData } = useConversationControls();
  const { status } = useConversationStatus();

  useEffect(() => {
    if (status !== "connected") return;
    let raf = 0;
    const ctx = canvasRef.current!.getContext("2d")!;
    const draw = () => {
      const data = getInputByteFrequencyData();
      ctx.clearRect(0, 0, canvasRef.current!.width, canvasRef.current!.height);
      data.forEach((v, i) => {
        const h = (v / 255) * canvasRef.current!.height;
        ctx.fillRect(i * 3, canvasRef.current!.height - h, 2, h);
      });
      raf = requestAnimationFrame(draw);
    };
    draw();
    return () => cancelAnimationFrame(raf);
  }, [status, getInputByteFrequencyData]);

  return <canvas ref={canvasRef} width={300} height={60} />;
}
```

For a simple "pulsing dot" indicator, use the scalar `getInputVolume()`
or `getOutputVolume()` instead — also 0–255 scaled to 0–1:

```tsx
function VolumeDot() {
  const { getOutputVolume } = useConversationControls();
  const [v, setV] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setV(getOutputVolume()), 50);
    return () => clearInterval(id);
  }, [getOutputVolume]);
  return <div style={{ transform: `scale(${1 + v})` }} className="dot" />;
}
```

Don't poll faster than the screen refresh rate — `setInterval(_, 50)` is
20 fps, fine for ambient indicators. Use rAF for canvas drawing.

## Transcript rendering

Subscribe to `onMessage` in `startSession` or via the hook. Messages
arrive as `{ role: 'user' | 'agent', message: string }` (the older
`source: 'user' | 'ai'` is still present but deprecated — use `role`).
The same message can arrive multiple times as it's refined — keep them
keyed by sequence or just append final ones:

```tsx
function TranscriptPane() {
  const [messages, setMessages] = useState<{ role: string; text: string }[]>([]);
  const { startSession, endSession } = useConversationControls();

  const start = async () => {
    const { signedUrl } = await fetch("/api/voice/signed-url").then(r => r.json());
    startSession({
      signedUrl,
      onMessage: ({ role, message }) => {
        setMessages(m => [...m, { role, text: message }]);
      },
    });
  };

  return (
    <div>
      {messages.map((m, i) => (
        <div key={i} className={m.role === "user" ? "user-bubble" : "agent-bubble"}>
          {m.text}
        </div>
      ))}
      <button onClick={start}>Talk</button>
    </div>
  );
}
```

For word-level captioning (highlighting words as the agent speaks them),
use `onAudioAlignment`. Most apps don't need this.

`onAgentResponseCorrection` fires when the agent reworded a reply after
it was sent — useful if you want to show the "actually I should have said
X" correction, but most UIs ignore it.

## Typed-message fallback (`sendUserMessage`)

For accessibility (deaf users, public quiet spaces) or when speech recognition
is failing, accept typed input that the agent treats as if the user spoke it:

```tsx
function TextFallback() {
  const { sendUserMessage } = useConversationControls();
  const [text, setText] = useState("");

  return (
    <form onSubmit={e => { e.preventDefault(); sendUserMessage(text); setText(""); }}>
      <input value={text} onChange={e => setText(e.target.value)} placeholder="Or type instead…" />
      <button type="submit">Send</button>
    </form>
  );
}
```

This sends the text as a user turn — the agent will reply (with voice or
text per session config). Use this for accessibility, not for general
chat-style messaging; for that, use ElevenAgents in text mode or your
existing chat UI.

## Background context (`sendContextualUpdate`)

`sendContextualUpdate(text)` pushes info to the agent's context **without
prompting a reply**. The agent receives it as background knowledge for
future turns. Use it for:

- User just navigated to a different page / section
- Cart total changed
- An async operation the agent triggered completed
- Identity loaded after auth ("user is John Smith, premium tier")

```tsx
function PageContext() {
  const { sendContextualUpdate } = useConversationControls();
  const pathname = usePathname();

  useEffect(() => {
    sendContextualUpdate(`User is now on page: ${pathname}`);
  }, [pathname, sendContextualUpdate]);

  return null;
}
```

Do not use this for messages the agent should respond to — use
`sendUserMessage` for that. Mixing them up makes the agent narrate page
navigations ("Ah, I see you're on the checkout page…").

## Conversation overrides at start

Each override field must be **enabled in the dashboard's Overrides tab
first** or the value is silently ignored. Common overrides:

```tsx
startSession({
  signedUrl,
  overrides: {
    agent: {
      prompt: { prompt: "You are helping the user practice ordering food in Italian." },
      firstMessage: "Ciao! Cosa vorresti ordinare oggi?",
      language: "it",                              // forces the agent's reply language
    },
    tts: {
      voiceId: "21m00Tcm4TlvDq8ikWAM",
      stability: 0.5,                              // 0-1, lower = more emotional range
      similarityBoost: 0.75,                       // 0-1, "Clarity + Similarity Enhancement"
    },
  },
});
```

Per-session overrides are the right place for per-user personalization
(name, language, role-play scenario). Don't put them in the dashboard
default if they vary per call.

## Client tools (UI-triggered actions)

Client tools are functions the agent can call in the browser/mobile app.
Use cases:

- Navigation: agent says "let me show you that page" → calls `navigateTo({ path })`
- Lookup: agent says "what's in your cart?" → calls `getCartContents()`
- Confirmation: agent calls `confirmPurchase()` → opens your modal

```tsx
startSession({
  signedUrl,
  clientTools: {
    navigateTo: async ({ path }: { path: string }) => {
      router.push(path);
      return "navigated";                          // returned to agent as tool result
    },
    showProduct: async ({ productId }: { productId: string }) => {
      setHighlightedProduct(productId);
      return JSON.stringify({ shown: true });
    },
  },
});
```

The tool name must match what the agent is configured to call (in
the dashboard's tools tab, or via `overrides.agent.tools`). Return
values are serialized and fed back to the agent. If you don't return
anything, the agent gets `undefined` and may say "I don't know if that
worked."

`onUnhandledClientToolCall` fires when the agent calls a tool you didn't
register — log it in dev, alert in prod (it's an agent-config drift).

## Feedback thumbs

After each agent turn, the user can optionally rate the response:

```tsx
function Feedback() {
  const { canSendFeedback, sendFeedback } = useConversationFeedback();
  if (!canSendFeedback) return null;
  return (
    <>
      <button onClick={() => sendFeedback("like")}>👍</button>
      <button onClick={() => sendFeedback("dislike")}>👎</button>
    </>
  );
}
```

`canSendFeedback` flips back to `false` after sending, until the next
agent turn. Show the buttons only when it's `true` to avoid duplicate
ratings.

## Device pickers

Let users choose mic and speaker:

```tsx
function DevicePickers() {
  const { changeInputDevice, changeOutputDevice } = useConversationControls();
  const [inputs, setInputs] = useState<MediaDeviceInfo[]>([]);
  const [outputs, setOutputs] = useState<MediaDeviceInfo[]>([]);

  useEffect(() => {
    navigator.mediaDevices.enumerateDevices().then(devs => {
      setInputs(devs.filter(d => d.kind === "audioinput"));
      setOutputs(devs.filter(d => d.kind === "audiooutput"));
    });
  }, []);

  return (
    <>
      <select onChange={e => changeInputDevice({ deviceId: e.target.value })}>
        {inputs.map(d => <option key={d.deviceId} value={d.deviceId}>{d.label}</option>)}
      </select>
      <select onChange={e => changeOutputDevice({ deviceId: e.target.value })}>
        {outputs.map(d => <option key={d.deviceId} value={d.deviceId}>{d.label}</option>)}
      </select>
    </>
  );
}
```

`enumerateDevices()` returns blank labels until the user has granted mic
permission once — show the pickers after the first `startSession()` or
gate them behind a "set up devices" button that first calls
`getUserMedia({ audio: true })`.
