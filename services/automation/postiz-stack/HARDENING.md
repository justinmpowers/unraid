# Hardening Notes

This document records the hardening changes applied to the stack and what still needs environment-specific validation.

## Applied Hardening

- Pinned infrastructure image tags:
  - postgres:17-alpine
  - redis:7.2
  - temporalio/auto-setup:1.28.1
  - docker.n8n.io/n8nio/n8n:1.123.56
  - ollama/ollama:0.12.1
- Postiz application image is set directly in compose as a single upstream app image.
- Current pin: ghcr.io/gitroomhq/postiz-app:v2.21.8.
- Added no-new-privileges to all services.
- Added GENERIC_TIMEZONE for n8n schedule consistency.
- Added N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true.
- Made Postiz API and frontend health paths configurable:
  - POSTIZ_API_HEALTH_PATH
  - POSTIZ_FRONTEND_HEALTH_PATH

## Upstream Verification Inputs

- Postiz upstream compose reference shows a single image path and current Temporal examples using auto-setup with pinned tags.
- Temporal Docker Hub marks auto-setup as deprecated in favor of server/admin-tools compose examples.
- n8n docs emphasize pinned versions, persisted user folder, and timezone env settings.

## Remaining Operator Validation

- Confirm final Postiz image references and exact tags/digests for your chosen release channel.
- Validate Postiz health endpoints against the exact image revision selected.
- Plan migration from temporalio/auto-setup to supported temporalio/server plus schema/admin tools when feasible.
- Add secret management strategy for OAuth client secrets and bot tokens.

## Recommended Next Security Steps

- Use digest pinning for all images.
- Move credentials to Docker secrets or file-backed envs where supported.
- Restrict network egress for internal services if your host firewall model supports it.
- Add periodic image vulnerability scanning in CI.
