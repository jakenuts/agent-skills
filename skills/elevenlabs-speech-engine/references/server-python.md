# Server — Python

The Python `elevenlabs` SDK exposes Speech Engine on both
`ElevenLabs` (sync) and `AsyncElevenLabs` — they share one
`SpeechEngineResource`. The resource's serving methods (`serve()`,
`create_session()`) are **async-only** because they hold long-lived
WebSocket connections, so in practice you'll be writing `async def` and
using `AsyncElevenLabs`. Your server is a WebSocket endpoint;
ElevenLabs connects to it per conversation.

## Contents
- [Install and import](#install-and-import)
- [Three ways to mount the server](#three-ways-to-mount-the-server)
- [Callbacks (`engine.serve()` mode)](#callbacks-engineserve-mode)
- [Event-based handlers (`create_session()` mode)](#event-based-handlers-create_session-mode)
- [Forwarding LLM streams](#forwarding-llm-streams)
- [Interruption via `asyncio.CancelledError`](#interruption-via-asynciocancellederror)
- [FastAPI / Starlette integration](#fastapi--starlette-integration)
- [Signed URL endpoint](#signed-url-endpoint)

## Install and import

```bash
pip install elevenlabs
```

```python
from elevenlabs import AsyncElevenLabs
from elevenlabs.speech_engine import SpeechEngineServer  # for standalone server
```

## Three ways to mount the server

### A. `engine.serve()` — standalone server with batteries

Fastest path. Opens a WebSocket server on the port you give it.

```python
import asyncio
from openai import AsyncOpenAI
from elevenlabs import AsyncElevenLabs

openai_client = AsyncOpenAI()
elevenlabs = AsyncElevenLabs()

async def main():
    engine = await elevenlabs.speech_engine.get("seng_123")

    async def on_transcript(transcript, session):
        stream = await openai_client.responses.create(
            model="gpt-4o",
            input=[
                {"role": "assistant" if m.role == "agent" else m.role, "content": m.content}
                for m in transcript
            ],
            stream=True,
        )
        await session.send_response(stream)

    async def on_init(conversation_id, session):
        print(f"Session started: {conversation_id}")

    async def on_close(session):
        print(f"Session ended: {session.conversation_id}")

    async def on_error(err, session):
        print(f"Error: {err}")

    # serve() is keyword-only — positional args raise TypeError
    await engine.serve(
        port=3001,
        debug=True,
        on_init=on_init,
        on_transcript=on_transcript,
        on_close=on_close,
        on_error=on_error,
    )

asyncio.run(main())
```

### B. `engine.create_session(ws)` — integrate with FastAPI / Starlette / any ASGI

Use when you already have a web app and want Speech Engine on one route.

```python
from fastapi import FastAPI, WebSocket
from elevenlabs import AsyncElevenLabs

app = FastAPI()
elevenlabs = AsyncElevenLabs()
engine = None  # initialize on startup

@app.on_event("startup")
async def setup():
    global engine
    engine = await elevenlabs.speech_engine.get("seng_123")

@app.websocket("/api/speech-engine/ws")
async def speech_engine_ws(ws: WebSocket):
    await ws.accept()
    session = engine.create_session(ws, debug=True)

    @session.on("user_transcript")
    async def handle_transcript(transcript):
        # session is already in scope — not passed as arg here
        stream = await llm_call(transcript)
        await session.send_response(stream)

    await session.run()                              # blocks until close
```

### C. `SpeechEngineServer` — full lifecycle control

Use when you need `start` / `stop` controlled by your own supervisor
(systemd, k8s preStop hook, signal handlers).

```python
from elevenlabs.speech_engine import SpeechEngineServer

server = SpeechEngineServer(
    port=3001,
    debug=True,
    on_transcript=handle_transcript,
)

# in one task
await server.serve()

# in another (e.g. signal handler)
await server.stop()
```

## Callbacks (`engine.serve()` mode)

| Callback | Args | Description |
|----------|------|-------------|
| `on_init` | `(conversation_id: str, session: Session)` | Session opened |
| `on_transcript` | `(transcript: list[Message], session: Session)` | User just spoke |
| `on_close` | `(session: Session)` | Clean disconnect by ElevenLabs |
| `on_disconnect` | `(session: Session)` | Unexpected WS drop |
| `on_error` | `(err: Exception, session: Session)` | Error |

All are `async def`. `Message` has `.role` (`'user' | 'agent'`) and
`.content` (`str`).

## Event-based handlers (`create_session()` mode)

When you call `engine.create_session(ws)` directly, register handlers via
`session.on(event_name)`. The `session` argument is dropped from the
signatures — you already hold the reference:

| Event | Handler signature |
|-------|-------------------|
| `"init"` | `async (conversation_id: str) -> None` |
| `"user_transcript"` | `async (transcript: list[ConversationMessage]) -> None` |
| `"close"` | `async () -> None` |
| `"disconnected"` | `async () -> None` |
| `"error"` | `async (error: Exception) -> None` |

## Forwarding LLM streams

`session.send_response()` accepts strings, async iterators, and native
LLM stream objects (OpenAI, Anthropic, Gemini auto-detected).

```python
# Plain string
await session.send_response("Hello world")

# OpenAI Responses API stream
stream = await openai_client.responses.create(model="gpt-4o", input=[...], stream=True)
await session.send_response(stream)

# OpenAI chat completions stream
stream = await openai_client.chat.completions.create(
    model="gpt-4o-mini", messages=[...], stream=True,
)
await session.send_response(stream)

# Anthropic
async with anthropic_client.messages.stream(model="claude-sonnet-4-6", messages=[...]) as stream:
    await session.send_response(stream)

# Any async iterator of strings
async def gen():
    yield "Hello "
    yield "world."

await session.send_response(gen())
```

Role mapping (same as TypeScript):

```python
input=[
    {"role": "assistant" if m.role == "agent" else m.role, "content": m.content}
    for m in transcript
]
```

## Interruption via `asyncio.CancelledError`

When the user interrupts, the SDK cancels the in-flight handler task.
`asyncio.CancelledError` is raised at the next `await`. **Let it
propagate** — that's how the cancellation reaches your LLM client and
actually aborts the request.

```python
async def on_transcript(transcript, session):
    # If user interrupts here, CancelledError raises during this await
    # and propagates into the OpenAI client, aborting the HTTP request.
    stream = await openai_client.responses.create(
        model="gpt-4o", input=..., stream=True,
    )
    await session.send_response(stream)
```

Pitfalls:

```python
# WRONG: swallows cancellation, LLM request keeps running, costs money
try:
    stream = await openai_client.responses.create(...)
    await session.send_response(stream)
except Exception as e:                              # <-- catches CancelledError too
    log.error(e)

# RIGHT: re-raise CancelledError, log everything else
try:
    stream = await openai_client.responses.create(...)
    await session.send_response(stream)
except asyncio.CancelledError:
    raise
except Exception as e:
    log.error(e)
```

`asyncio.CancelledError` does NOT inherit from `Exception` in Python
3.8+, so a bare `except Exception` won't actually catch it — but
`except BaseException` or `except:` will. Don't use those in the
handler.

## FastAPI / Starlette integration

Full example with signed URL endpoint:

```python
import os
from contextlib import asynccontextmanager
from fastapi import FastAPI, WebSocket
from openai import AsyncOpenAI
from elevenlabs import AsyncElevenLabs

openai_client = AsyncOpenAI()
elevenlabs = AsyncElevenLabs(api_key=os.environ["ELEVENLABS_API_KEY"])
engine = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global engine
    engine = await elevenlabs.speech_engine.get("seng_123")
    yield

app = FastAPI(lifespan=lifespan)

@app.websocket("/api/speech-engine/ws")
async def ws_endpoint(ws: WebSocket):
    await ws.accept()
    session = engine.create_session(ws, debug=True)

    @session.on("user_transcript")
    async def on_user(transcript):
        stream = await openai_client.responses.create(
            model="gpt-4o",
            input=[
                {"role": "assistant" if m.role == "agent" else m.role, "content": m.content}
                for m in transcript
            ],
            stream=True,
        )
        await session.send_response(stream)

    await session.run()

@app.get("/api/voice/signed-url")
async def signed_url():
    url = await elevenlabs.conversational_ai.conversations.get_signed_url(
        agent_id="agent_abc",
    )
    return {"signed_url": url}
```

Run with `uvicorn main:app --host 0.0.0.0 --port 3000`.

## Signed URL endpoint

The browser/mobile client should never see your API key. Generate a
short-lived (15-min) signed URL server-side:

```python
url = await elevenlabs.conversational_ai.conversations.get_signed_url(
    agent_id="agent_abc",
)
```

For WebRTC clients (React Native, modern browsers preferring WebRTC),
use a WebRTC token:

```python
token = await elevenlabs.conversational_ai.conversations.get_webrtc_token(
    agent_id="agent_abc",
)
```

The SDK method is `get_webrtc_token`, but the client option you pass
into `startSession()` is still spelled `conversationToken`.

The agent ID (`agent_*`) is separate from the engine ID (`seng_*`) — the
agent is what the client connects to; the engine is what serves
transcripts to your server. Both are wired together in the dashboard. See
[dashboard-and-deployment.md](dashboard-and-deployment.md).

## Managing engines from code

You don't have to use the dashboard for engine config. The
`speech_engine` resource exposes CRUD:

```python
# Create
engine = await elevenlabs.speech_engine.create(
    name="my-engine",
    server_url="wss://api.mycompany.com/api/speech-engine/ws",
    # plus AsrConversationalConfig, BaseTurnConfig, TtsConversationalConfigInput
)

# Read (also populates engine.config)
engine = await elevenlabs.speech_engine.get("seng_123")
print(engine.config)

# Update
await elevenlabs.speech_engine.update("seng_123", server_url="...")
```

Use this for infra-as-code, environment promotion (dev → staging →
prod with the same engine ID generated server-side), and per-tenant
engine provisioning.
