# Home Assistant

## Quick start
1. Copy `.env.example` to `.env` and update values (including `UNRAID_HOST_IP`).
2. Start the stack.

## Networking
`home-assistant` stays on `iot_net` (bridge networking) behind Traefik as usual,
via `homeassistant.${DOMAIN}`. `matter-server` and `esphome` run on
`network_mode: host` for mDNS/Zeroconf discovery (matter-server needed it
already; esphome needs it to find and adopt devices).

Trade-off: because `home-assistant` itself is *not* on host networking, it
won't auto-discover ESPHome devices (e.g. Voice PE) via mDNS the way it would
on host mode - you won't get the automatic "Discovered device" card for the
ESPHome integration. Two ways around that:
- Adopt the device in the `esphome` dashboard first (it can discover it via
  its own host networking), note the IP it's adopted at, then in Home
  Assistant go to Settings → Devices & Services → Add Integration → ESPHome
  and enter that IP manually.
- Voice PE's initial pairing (Bluetooth + Wi-Fi provisioning via the HA
  frontend/companion app) doesn't rely on mDNS discovery either way, so
  first-time setup should work regardless.

If you ever want full auto-discovery in Home Assistant itself, see this
service's git history for the host-networking + Traefik file-provider
approach that was tried and reverted.

## ESPHome Dashboard
`esphome` is the standalone ESPHome Dashboard (what Home Assistant's docs call
"the ESPHome app"), used to adopt devices and edit their YAML config - e.g. to
[tweak Voice PE's audio settings](https://www.home-assistant.io/voice_control/troubleshooting/#to-tweak-the-assist-audio-configuration-for-your-device)
(noise suppression, auto gain, volume). The Supervisor-only "ESPHome" Add-on
isn't available on Container installs, so this container replaces it.

Runs on `network_mode: host` (see Networking above) for mDNS device
discovery/adoption and OTA updates. It isn't routed through Traefik - open it
directly at `http://${UNRAID_HOST_IP}:6052`. Set
`ESPHOME_USERNAME`/`ESPHOME_PASSWORD` in `.env` if you want the dashboard
password-protected.

To adopt Voice PE: open the dashboard, it should show the device under
"Discovered" once it's on the network - click **Adopt**, then **Edit** to add
the `voice_assistant:` audio tuning block from the troubleshooting doc above.

## Local voice processing (Whisper + Piper)
`wyoming-whisper` (speech-to-text) and `wyoming-piper` (text-to-speech) let
Assist run fully locally instead of using Nabu Casa's cloud STT/TTS. Both sit
on `iot_net` with `home-assistant`, so no IP juggling is needed - they're
reachable by container name and default Wyoming port.

Set up in Home Assistant:
1. Settings → Devices & Services → **Add Integration** → **Wyoming Protocol**
   - Host `wyoming-whisper`, port `10300`
   - Repeat: Host `wyoming-piper`, port `10200`
2. Settings → Voice Assistants → **Add Assistant**
   - Conversation agent: Home Assistant (built-in) or your choice
   - Speech-to-text: Whisper (the entry you just added)
   - Text-to-speech: Piper (the entry you just added)
3. Assign this pipeline to Voice PE's `assist_satellite` entity (its device
   page → gear icon → pick the pipeline, or leave it on "Preferred assistant"
   if this is your only pipeline).

Tuning: `WHISPER_MODEL`/`WHISPER_LANGUAGE` and `PIPER_VOICE` in `.env` control
which models get downloaded on first start (into
`${HOME_ASSISTANT_PATH}/wyoming-whisper` and `.../wyoming-piper`, so re-pulls
aren't needed after container recreation). Browse Piper voices at
https://rhasspy.github.io/piper-samples/. `tiny-int8` is the fastest Whisper
model on CPU-only hardware; step up to `base-int8` or `small-int8` for better
accuracy if responses feel slow to arrive or transcription is inaccurate.
