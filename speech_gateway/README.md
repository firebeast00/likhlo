# Likhlo Speech Gateway Pilot

This gateway keeps Google credentials out of the Flutter application and
streams authenticated audio to Speech-to-Text V2 `chirp_3`.

Required environment:

- `GOOGLE_CLOUD_PROJECT`
- `CHIRP_LOCATION` (`eu` by default; verify current `ur-PK` availability)
- Application Default Credentials for Google Cloud and Firebase Admin

Clients must send a valid Firebase ID token in the WebSocket `Authorization`
header. Raw audio and transcripts are not logged. The Flutter cloud provider
is intentionally not enabled by default; device recognition remains active
until a gateway URL, short-lived identity token, and microphone PCM source are
configured and the Pakistani benchmark passes.
