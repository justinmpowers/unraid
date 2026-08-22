# Music Assistant

[Music Assistant](https://www.music-assistant.io/) is a media library manager
that connects your streaming services and local media to a wide range of players
(Sonos, Chromecast, AirPlay, DLNA, Snapcast, and Home Assistant media players),
with a tight two-way Home Assistant integration.

## Quick start
1. Copy `.env.example` to `.env` and update values (or deploy with the shared
   root `.env` via `--env-file ../../../.env`).
2. Start the stack:
   ```bash
   cd services/iot/music-assistant
   docker-compose --env-file ../../../.env up -d
   ```
3. Open the web UI at `http://<unraid-host-ip>:8095` and complete onboarding.

## Networking
This container runs with `network_mode: host`. Music Assistant needs to be on
the same L2 network as your players to discover them and stream audio via
mDNS/multicast, so it deliberately does **not** sit on `iot_net` behind Traefik
the way the other web UIs do (same reason `govee2mqtt` and `obico`'s `ankerctl`
use host networking).

Key ports (all bound directly on the host):
- `8095` – web UI and API
- `8097` – built-in stream server (audio delivered to players)

Because it uses host networking there's no Traefik router; reach the UI at
`http://<unraid-host-ip>:8095`. Uptime Kuma monitors it over HTTP on the same
port.

## Home Assistant integration
Music Assistant exposes a native Home Assistant integration:
1. In Home Assistant: Settings → Devices & Services → **Add Integration** →
   **Music Assistant**.
2. When prompted for the server URL, enter `http://<unraid-host-ip>:8095`
   (auto-discovery over mDNS should also surface it since both are on the LAN).
3. Your Music Assistant players then appear as `media_player` entities in Home
   Assistant, usable in automations, dashboards, and Assist ("play … in the
   kitchen").

## Data & configuration
- All state (database, settings, provider credentials, cache) lives in
  `${APPDATA_PATH}/music-assistant` mounted at `/data`, so it survives container
  recreation and is backed up with the rest of appdata.
- Streaming providers (Spotify, Apple Music, YouTube Music, Tidal, etc.) and
  players are added from the web UI under Settings after first start — no
  environment configuration is required for them.

## Local music library (optional)
No local library is mounted by default. To add one, mount your music share
read-only and point Music Assistant at `/media` in the UI. Example addition to
the service in `docker-compose.yml`:
```yaml
    volumes:
      - ${APPDATA_PATH}/music-assistant:/data
      - /etc/localtime:/etc/localtime:ro
      - /mnt/user/media/music:/media:ro
```
Then in the UI: Settings → Providers → add a **Filesystem** provider pointing at
`/media`. (SMB/NFS network shares mounted inside the container may additionally
need `cap_add: [DAC_READ_SEARCH]` and `security_opt: [apparmor:unconfined]`;
a local Unraid path like the above does not.)

## Tuning
`MUSIC_ASSISTANT_LOG_LEVEL` in `.env` controls verbosity (`debug`, `info`,
`warning`, `error`). Transcoding for multiple simultaneous players is the main
CPU cost; raise the `cpus` limit in `docker-compose.yml` if you stream to many
players at once.
