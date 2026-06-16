# Postiz + n8n + Ollama Architecture

This stack provides a decoupled automation system for social content generation, approval, scheduling, and telemetry normalization.

## Components

- Postiz single app service
- PostgreSQL and Redis for Postiz state
- Temporal for workflow durability
- n8n for orchestration and webhook approval loops
- Ollama for local content generation and analysis
- Etsy API v3 for listing and draft automation
- Telegram for human approval callbacks

## Runtime Topology

```mermaid
flowchart LR
  Etsy[Etsy API v3] --> n8n[n8n]
  n8n --> Ollama[Ollama Local LLM]
  n8n --> Telegram[Telegram Approval]
  n8n --> Postiz[Postiz App]
  Postiz --> PG[(PostgreSQL)]
  Postiz --> Redis[(Redis)]
  Postiz --> Temporal[Temporal]
  n8n --> Meta[Meta Graph API]
  n8n --> Pinterest[Pinterest v5 API]
```

## Sequence: Workflow A Generator

```mermaid
sequenceDiagram
  autonumber
  participant Cron as n8n Cron Trigger
  participant Etsy as Etsy API
  participant LLM as Ollama
  participant T as Telegram
  participant Wait as n8n Wait Node

  Cron->>Etsy: GET active listings
  Etsy-->>Cron: Listing payload
  Cron->>LLM: Generate caption drafts
  LLM-->>Cron: Draft content
  Cron->>Cron: Set PENDING_APPROVAL + resumeUrl
  Cron->>T: Send inline approval button
  T-->>Wait: User clicks approval link
  Wait-->>Cron: Resume execution payload
```

## Sequence: Workflow B Listener + Media Gate

```mermaid
sequenceDiagram
  autonumber
  participant U as Reviewer Browser
  participant B as n8n Workflow B
  participant P as Postiz App
  participant S as Postiz Scheduler

  U->>B: GET editor webhook
  B-->>U: HTML edit form
  U->>B: POST edited caption + media source
  B->>B: Validate media source
  B->>P: POST /api/uploads strict_validation=true
  P-->>B: Verified hosted media URL
  B->>S: POST /api/schedules
  S-->>B: Schedule accepted
  B-->>U: status=scheduled
```

## Sequence: Etsy Draft Creator Utility

```mermaid
sequenceDiagram
  autonumber
  participant Script as etsy-draft-creator.js
  participant Etsy as Etsy API

  Script->>Etsy: POST /v3/application/shops/{shop_id}/listings state=draft
  Etsy-->>Script: listing_id
  Script->>Etsy: POST /v3/application/shops/{shop_id}/listings/{listing_id}/images
  Etsy-->>Script: upload ok
  Script->>Etsy: PATCH /v3/application/shops/{shop_id}/listings/{listing_id} state=active
  Etsy-->>Script: listing active
```

## Data Rules and Constraints

- n8n workflows are split into two separate templates to avoid double-trigger constraints.
- Post publishing must pass through Postiz upload validation first.
- Local filesystem media paths and unverified external URLs are rejected for scheduling handoff.
- Analytics normalization runs before LLM prompt tuning and KPI reporting.

## Normalization Math

Instagram hourly correction:

$$
 h_{local} = (h_{api} + \Delta t_{local}) \bmod 24
$$

Pinterest organic CTR:

$$
 CTR = \left(\frac{OutboundClicks}{Impressions}\right) \times 100\%
$$
