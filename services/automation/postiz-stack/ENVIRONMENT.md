# Environment Contract

This file defines the full variable contract for the Postiz automation stack.

## Core host variables

- TZ: Host timezone, used by all services and scheduling logic.
- HOST_HOSTNAME: Unraid host display name.
- DOMAIN: Base domain used by Traefik host rules.
- APPDATA_PATH: Unraid persistent volume base path.

## Postiz service variables

- POSTIZ_JWT_SECRET: JWT signing secret for Postiz authentication.
- POSTIZ_DB_NAME: Postiz database name.
- POSTIZ_DB_USER: Postiz database user.
- POSTIZ_DB_PASSWORD: Postiz database password.
- POSTIZ_TEMPORAL_DB_NAME: Temporal schema database name.
- POSTIZ_HEALTH_PATH: Single Postiz app health endpoint path.

## n8n variables

- N8N_ENCRYPTION_KEY: Credential encryption key.

## Runtime workflow variables

- ETSY_SHOP_ID: Etsy shop identifier.
- ETSY_CLIENT_ID: Etsy client ID (also x-api-key value).
- ETSY_ACCESS_TOKEN: Etsy OAuth bearer token.
- TELEGRAM_APPROVAL_CHAT_ID: Telegram target chat/channel for approval link delivery.
- POSTIZ_BASE_URL: Internal URL for the single Postiz app service from n8n.
- OLLAMA_BASE_URL: Internal URL for Ollama from n8n.

## Etsy draft creator script variables

- ETSY_API_BASE_URL: Etsy API base URL.
- ETSY_LISTING_QUANTITY: Draft listing quantity.
- ETSY_LISTING_TITLE: Draft listing title.
- ETSY_LISTING_DESCRIPTION: Draft listing description.
- ETSY_LISTING_PRICE: Draft listing price.
- ETSY_WHO_MADE: Etsy who_made enum value.
- ETSY_WHEN_MADE: Etsy when_made enum value.
- ETSY_TAXONOMY_ID: Etsy taxonomy ID.
- ETSY_SHIPPING_PROFILE_ID: Etsy shipping profile ID.
- ETSY_LISTING_IMAGE_PATH: Local path used for uploadListingImage.
- DRY_RUN: true or false dry-run execution mode.

## OAuth integration placeholders

- META_APP_ID: Meta app ID for Graph integrations.
- META_APP_SECRET: Meta app secret.
- META_REDIRECT_URI: Meta OAuth redirect URI.
- PINTEREST_CLIENT_ID: Pinterest client ID.
- PINTEREST_CLIENT_SECRET: Pinterest client secret.
- PINTEREST_REDIRECT_URI: Pinterest redirect URI.

## Suggested baseline values

The generated local reference file is available at services/automation/postiz-stack/.env.example in your working directory for quick bootstrap values.
