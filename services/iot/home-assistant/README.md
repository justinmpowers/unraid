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
