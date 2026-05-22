# Client — React Native (iOS / Android)

`@elevenlabs/react-native` is a React Native wrapper around
`@elevenlabs/react`. The API is identical (same `ConversationProvider`,
same hooks) — the only differences are the native setup and that
**Expo Go is not supported**.

## Contents
- [Install (Expo dev build)](#install-expo-dev-build)
- [iOS permissions](#ios-permissions)
- [Android permissions](#android-permissions)
- [Same API as @elevenlabs/react](#same-api-as-elevenlabsreact)
- [WebRTC transport (LiveKit under the hood)](#webrtc-transport-livekit-under-the-hood)
- [Audio session and interruptions (phone calls, Siri)](#audio-session-and-interruptions-phone-calls-siri)

## Install (Expo dev build)

```bash
npm install @elevenlabs/react-native @livekit/react-native @livekit/react-native-webrtc livekit-client
```

The LiveKit packages provide the native WebRTC modules. They include
native iOS / Android code that **Expo Go does not bundle**. You must
use an Expo dev build (or bare React Native):

```bash
npx expo install expo-dev-client
npx expo prebuild
npx expo run:ios     # or run:android
```

If a user reports "no audio in Expo Go", that's the cause. Switch to
a dev build.

## iOS permissions

Add to `ios/<App>/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs access to your microphone for voice conversations.</string>
```

Or via Expo config (`app.json`):

```json
{
  "expo": {
    "ios": {
      "infoPlist": {
        "NSMicrophoneUsageDescription": "This app needs access to your microphone for voice conversations."
      }
    }
  }
}
```

The user-facing prompt string is required by Apple; missing it crashes
on iOS 14+ when the SDK requests the mic.

## Android permissions

`android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
```

`BLUETOOTH_CONNECT` is needed on Android 12+ to use Bluetooth headsets.

For Expo, set via `app.json`:

```json
{
  "expo": {
    "android": {
      "permissions": [
        "RECORD_AUDIO",
        "MODIFY_AUDIO_SETTINGS",
        "BLUETOOTH_CONNECT"
      ]
    }
  }
}
```

On Android 6.0+ runtime permissions are also required (`PermissionsAndroid.request`).
The SDK requests `RECORD_AUDIO` itself on `startSession()`, but only if
the manifest declares it.

## Same API as @elevenlabs/react

The React Native package re-exports everything from `@elevenlabs/react`.
Use the same hooks:

```tsx
import {
  ConversationProvider,
  useConversationControls,
  useConversationStatus,
  useConversationMode,
} from "@elevenlabs/react-native";
import { Button, Text, View } from "react-native";

export default function App() {
  return (
    <ConversationProvider>
      <VoiceScreen />
    </ConversationProvider>
  );
}

function VoiceScreen() {
  const { startSession, endSession } = useConversationControls();
  const { status } = useConversationStatus();
  const { isSpeaking } = useConversationMode();

  const start = async () => {
    const res = await fetch("https://your-server.com/api/voice/conversation-token");
    const { conversationToken } = await res.json();
    startSession({ conversationToken });           // WebRTC on mobile
  };

  return (
    <View>
      <Text>Status: {status}{isSpeaking && " (speaking)"}</Text>
      <Button title="Talk" onPress={start} disabled={status !== "disconnected"} />
      <Button title="Stop" onPress={() => endSession()} />
    </View>
  );
}
```

Method shapes (`sendUserMessage`, `sendContextualUpdate`, `setVolume`,
`getInputByteFrequencyData`, etc.) are identical to the web package.

## WebRTC transport (LiveKit under the hood)

Mobile uses WebRTC exclusively. You authenticate with a
**conversation token**, not a signed URL:

```tsx
startSession({ conversationToken });
```

If your server-side example uses `getSignedUrl({ agentId })`, switch to
`getConversationToken({ agentId })` for mobile clients. The token is
short-lived (15 min), same as the signed URL — connect inside that
window.

`@livekit/react-native-webrtc` provides the WebRTC stack;
`@livekit/react-native` plus `livekit-client` wrap it. You should not
import LiveKit APIs directly — the ElevenLabs SDK manages the
connection. They're peer deps purely so you get to control the version.

## Audio session and interruptions (phone calls, Siri)

The SDK configures `AVAudioSession` on iOS automatically. Default
behavior:

- iOS: category `playAndRecord`, mode `voiceChat` — plays through the
  earpiece by default. Add `defaultToSpeaker` if you want speaker-on-by-default.
- Phone call coming in → session is interrupted by the OS. Listen for
  `onDisconnect` and reconnect after the call.
- Siri activation → same as a phone call.
- Background → audio session pauses. If your app supports voice in the
  background, add `audio` to `UIBackgroundModes` in `Info.plist`. Without
  it, iOS suspends the WebRTC connection within ~10s of backgrounding.

Android: the audio focus is managed via `AudioManager`. Headphone unplug
and Bluetooth disconnect events are not surfaced by the SDK — listen via
`react-native`'s `DeviceEventEmitter` or a library like
`react-native-system-setting` if your UX needs to react.

For an end-to-end working example, the official Expo sample app lives in
the `elevenlabs/packages` monorepo at `examples/react-native-expo`.
