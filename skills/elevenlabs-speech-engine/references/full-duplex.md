# Full-duplex behavior — turn-taking, barge-in, latency

A "voice interface" that only works in strict request/response feels
broken to users. ElevenLabs handles full-duplex (both sides can speak
at once) and barge-in (user interrupts the agent) at the platform
level. Your job is to (a) not fight the platform, (b) configure the
small set of knobs that ARE exposed, and (c) pick models with first-byte
latency in mind.

## Contents
- [What the platform does for you (no code)](#what-the-platform-does-for-you-no-code)
- [What you have to do (the abort signal)](#what-you-have-to-do-the-abort-signal)
- [What's configurable — and what isn't](#whats-configurable--and-what-isnt)
- [Latency budget](#latency-budget)
- [Model and voice picks](#model-and-voice-picks)
- [Streaming discipline](#streaming-discipline)
- [Backchannels and false interruptions](#backchannels-and-false-interruptions)
- [Debugging conversational feel](#debugging-conversational-feel)

## What the platform does for you (no code)

The ElevenLabs audio pipeline runs five subsystems in series on every
conversation:

1. **STT** — streaming speech-to-text on the user's audio
2. **VAD** — voice activity detection (is the user speaking?)
3. **Turn detection** — hybrid VAD + deep-learning model that looks at
   filler words, prosody, rhythm, micro-pauses to decide "the user's
   turn is over"
4. **Interruption detection** — if the user starts speaking while the
   agent is mid-reply, cuts the TTS, cancels the in-flight LLM call,
   and emits a fresh `user_transcript`
5. **TTS** — streams synthesized audio of your reply back to the client

You do not orchestrate any of this. There is no "wait for user to
finish" or "should I interrupt?" decision on your side.

## What you have to do (the abort signal)

The one thing the SDK can't do for you: cancel the LLM HTTP request
when the user interrupts. You have to pass the abort signal through.

**TypeScript:**

```ts
async onTranscript(transcript, signal, session) {
  const stream = await openai.responses.create(
    { model: "gpt-4o", input: [...], stream: true },
    { signal },                                    // ← without this, you keep paying tokens
  );
  session.sendResponse(stream);
}
```

**Python** — the cancellation arrives as `asyncio.CancelledError` at the
next `await`. Don't swallow it (see [server-python.md](server-python.md)).

If you skip this step, the symptoms are:

- The user interrupts and the audio stops (good)
- But the LLM call keeps generating in the background (bad — token cost,
  log noise)
- The next turn races with the still-in-flight call's `session.sendResponse`
  potentially landing late, after the user's new transcript was processed
  (very bad — agent sounds confused)

## What's configurable — and what isn't

**Configurable (dashboard, "Conversation flow" tab):**

| Setting | Range | Meaning |
|---------|-------|---------|
| Turn eagerness | Eager / Normal / Patient | How quickly the agent jumps in when the user pauses |
| Turn timeout | 1–30 s | How long to wait in silence before prompting |
| Interruption sensitivity | enable/disable per agent | Whether user speech mid-reply cancels the agent |
| Language detection | on/off + allowed languages | Auto-switch language mid-conversation |

**Not configurable** (don't waste time looking):

- VAD score threshold
- "No interrupt window" (period at start of agent reply where user
  speech is ignored)
- Backchannel suppression ("uh-huh" / "yeah" / "right" not stopping the
  agent)
- Overlapping speech resolution rules
- STT model selection (it's a single ElevenLabs model)

If the use case needs any of those (call-center backchannel handling,
noisy environments with high false-positive interrupts), the platform
is the wrong tool — escalate to the user before building. Custom STT +
your own turn-taking on top of ElevenLabs raw audio APIs is theoretically
possible but defeats the purpose of Speech Engine.

## Latency budget

User perception of "conversational" breaks down above ~1 second from
end-of-user-speech to start-of-agent-audio. ElevenLabs' published
targets:

| Stage | Best case | Typical |
|-------|-----------|---------|
| End-of-turn detection | 100–300 ms | ~300 ms |
| LLM first token | 200–1000 ms | 700 ms (GPT-4 / Claude) — 350 ms (Gemini Flash) |
| TTS first byte | 75 ms (Flash) | 135 ms e2e (Flash) — 300 ms (Turbo) |
| Network RTT (client ↔ ElevenLabs ↔ your server) | 50 ms | 100–200 ms |

Sub-second end-to-end is achievable with Flash TTS + a fast LLM (Gemini
Flash, GPT-4o-mini, Claude Haiku) and co-located regions. Above 1.5 s
the conversation feels like a walkie-talkie.

## Model and voice picks

TTS models (set in dashboard, per agent):

| Model | First-byte latency | Languages | Use for |
|-------|-------------------|-----------|---------|
| `eleven_flash_v2_5` | ~135 ms e2e | 32 | Real-time chat / assistant default |
| `eleven_turbo_v2_5` | ~300 ms | 32 | Balanced quality + speed |
| `eleven_multilingual_v2` | higher | 29 | When quality matters more than latency |
| `eleven_v3` | higher | 70+ | Dramatic delivery, multi-speaker dialogue |

Default to Flash for interactive voice. Drop to Multilingual v2 only
when the user explicitly asks for higher fidelity (audiobook, character
voices, podcast-style).

LLM picks — keep first-token latency in mind:

- **Sub-500 ms first token**: Gemini Flash, GPT-4o-mini, Claude Haiku,
  Llama 3 on Groq
- **500–1000 ms first token**: GPT-4o, Claude Sonnet 4.x, Gemini Pro
- **Over 1000 ms**: long-context Claude Opus, large RAG-prompted GPT-4
  variants

Stick to the cheap-and-fast tier unless the user has explicitly traded
latency for capability. If the custom agent is a LangGraph workflow with
multiple LLM calls per turn, parallelize where possible and surface
partial responses early.

## Streaming discipline

`session.sendResponse(stream)` streams text as it arrives. Two patterns
that defeat this:

```ts
// WRONG: buffers the full response before sending — kills first-byte latency
const stream = await openai.responses.create({ ..., stream: true }, { signal });
let full = "";
for await (const chunk of stream) full += chunk.delta;
session.sendResponse(full);

// RIGHT: pass the stream object directly
const stream = await openai.responses.create({ ..., stream: true }, { signal });
session.sendResponse(stream);
```

```ts
// WRONG: await before passing — same problem
const result = await llmCall();                    // fully waits
session.sendResponse(result);

// RIGHT: stream end-to-end
const stream = llmCall({ stream: true });          // returns AsyncIterable
session.sendResponse(stream);
```

If you must transform tokens (filter, redact, prepend a sentence), do
it lazily:

```ts
async function* transform(stream: AsyncIterable<string>) {
  yield "Sure, ";                                  // first byte goes out immediately
  for await (const chunk of stream) yield chunk;
}
session.sendResponse(transform(rawStream));
```

## Backchannels and false interruptions

The platform's turn detection model is good but not perfect. Users
saying "uh-huh", "yeah", "right" while the agent is speaking can trigger
a false interruption. Mitigations:

- Set turn eagerness to **Patient** in the dashboard — the model waits
  longer for a "real" turn before cutting in
- Train users (via the `firstMessage` override) to "say 'stop' to
  interrupt me" so they only use intentional barge-in words
- Don't try to suppress backchannels in your `onTranscript` handler —
  by the time you see them, audio playback has already been cancelled

If false interrupts are blocking deployment, that's the limit of the
platform. Escalate.

## Debugging conversational feel

| Symptom | Probable cause |
|---------|----------------|
| Agent waits too long after I stop talking | Turn eagerness = Patient; set Normal or Eager |
| Agent talks over me sometimes | Turn eagerness = Eager; set Normal or Patient |
| First word of reply is delayed > 1 s | LLM first-token latency. Swap to a faster model or trim the prompt |
| First word is fast but speech is choppy | TTS chunk delivery. Confirm `session.sendResponse(stream)` not `(string)`; check network RTT |
| Agent interrupts itself / agent's TTS plays then is cut off | LLM call still streaming after a user interrupt → you forgot to pass `signal` |
| User interrupts with a single word and agent restarts whole reply | Working as designed; lower turn eagerness if it's too eager |
| `onModeChange` stuck in `listening` after user speaks | Server isn't returning a response — check `onTranscript` is firing and `session.sendResponse` is being called |
| Long pauses mid-reply | LLM streaming gap. Some models have token bursts then stalls — surface partial reply early with `yield "Hmm, "` |

`onVadScore` and `onInterruption` callbacks are useful for client-side
diagnostics — log them during tuning, remove before production unless
you need them for visualization.
