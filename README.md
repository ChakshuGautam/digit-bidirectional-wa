# WhatsApp Bidirectional Notifications

DIGIT WhatsApp notification system using Novu for outbound delivery.

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   PGR Service   │────▶│     Kafka        │────▶│  Novu Bridge    │
└─────────────────┘     └──────────────────┘     └────────┬────────┘
                                                          │
                        ┌─────────────────────────────────┼─────────────────────────────────┐
                        │                                 │                                 │
                        ▼                                 ▼                                 ▼
                ┌───────────────┐              ┌──────────────────┐              ┌─────────────────┐
                │ Config Service│              │ User Preferences │              │   Novu API      │
                │  (Templates)  │              │    (Consent)     │              │  (WhatsApp)     │
                └───────────────┘              └──────────────────┘              └─────────────────┘
```

## Services

| Service | Port | Description |
|---------|------|-------------|
| digit-user-preferences | 18200 | User consent and language preferences |
| digit-config-service | 18201 | Templates, policies, and notification configs |
| digit-novu-bridge | 18202 | Kafka consumer, policy enforcement, Novu triggering |
| baileys-provider | 18203 | WhatsApp Personal via Baileys (for local testing) |

## Novu Infrastructure

| Service | Port | Description |
|---------|------|-------------|
| novu-api | 13000 | Novu REST API |
| novu-web | 14200 | Novu Dashboard (UI) |
| novu-ws | 13002 | WebSocket server |
| novu-mongodb | 27017 | Novu database |

## Quick Start

```bash
# From the main project directory
cd /root/code/digit-2.9lts-core-storm

# Start Tilt (includes all services)
tilt up

# Access services:
# - Novu Dashboard: http://localhost:14200
# - User Preferences: http://localhost:18200/user-preferences/health
# - Config Service: http://localhost:18201/configs/health
# - Novu Bridge: http://localhost:18202/novu-bridge/health
```

## Hot Reload

The three WhatsApp services have hot-reload enabled:
- Edit files in `whatsapp/services/*/src/`
- Changes auto-reload via `tsx watch`

## API Examples

### Create User Preference (Consent)
```bash
curl -X POST http://localhost:18200/user-preferences/v1/_upsert \
  -H "Content-Type: application/json" \
  -d '{
    "requestInfo": {},
    "preference": {
      "userId": "user-123",
      "tenantId": "pg.citya",
      "preferenceCode": "USER_NOTIFICATION_PREFERENCES",
      "payload": {
        "preferredLanguage": "en_IN",
        "consent": {
          "WHATSAPP": { "status": "GRANTED", "scope": "GLOBAL" }
        }
      }
    }
  }'
```

### Create Config (Template)
```bash
curl -X POST http://localhost:18201/configs/v1/_create \
  -H "Content-Type: application/json" \
  -d '{
    "requestInfo": {},
    "config": {
      "tenantId": "pg.citya",
      "namespace": "notification-orchestrator",
      "configName": "PGR Created Template",
      "configCode": "TEMPLATE_PGR_CREATED",
      "version": "1.0.0",
      "status": "ACTIVE",
      "content": {
        "templates": {
          "en_IN": "Your complaint {{complaintNumber}} has been registered. Track at: {{trackingUrl}}",
          "hi_IN": "आपकी शिकायत {{complaintNumber}} दर्ज हो गई है। ट्रैक करें: {{trackingUrl}}"
        }
      }
    }
  }'
```

### Trigger Notification (Manual Test)
```bash
curl -X POST http://localhost:18202/novu-bridge/v1/_trigger \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "PGR_CREATED",
    "tenantId": "pg.citya",
    "recipient": {
      "userId": "user-123",
      "phone": "+919876543210"
    },
    "data": {
      "complaintNumber": "PGR-2026-001234",
      "trackingUrl": "https://pgr.example.com/track/001234"
    }
  }'
```

## Baileys Provider (Local WhatsApp Testing)

The Baileys provider allows you to send WhatsApp messages using your personal WhatsApp account for testing - no WhatsApp Business API required.

### First-Time Setup

1. Start Tilt: `tilt up`
2. Open QR page: http://localhost:18203/baileys/qr/page
3. Open WhatsApp on your phone → Settings → Linked Devices → Link a Device
4. Scan the QR code
5. You're connected! Session is persisted (no re-scan needed after restart)

### Baileys Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/baileys/health` | GET | Health check |
| `/baileys/qr/page` | GET | QR code page (scan to authenticate) |
| `/baileys/qr` | GET | QR code as JSON (data URL) |
| `/baileys/status` | GET | Connection status |
| `/baileys/send` | POST | Send message: `{ to: "+919876543210", content: "Hello" }` |
| `/baileys/disconnect` | POST | Logout from WhatsApp |
| `/baileys/reconnect` | POST | Force reconnection |

### Testing with Baileys

```bash
# Check status
curl http://localhost:18203/baileys/status

# Send message to yourself
curl -X POST http://localhost:18203/baileys/send \
  -H "Content-Type: application/json" \
  -d '{
    "to": "+919876543210",
    "content": "Test message from DIGIT!"
  }'
```

### Baileys vs Novu

| Mode | Use Case | Config |
|------|----------|--------|
| Baileys | Local testing, personal WhatsApp | `USE_BAILEYS=true` (default) |
| Novu | Production, WhatsApp Business API | Set `NOVU_API_KEY`, unset `USE_BAILEYS` |

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| USE_BAILEYS | true | Use Baileys for WhatsApp (local testing) |
| BAILEYS_PROVIDER_URL | http://baileys-provider:8203 | Baileys service URL |
| NOVU_API_KEY | - | Novu API key (for production) |
| KAFKA_BROKERS | kafka:9092 | Kafka broker addresses |
| KAFKA_TOPICS | pgr-create,pgr-update | Topics to consume |

### Novu Setup

1. Access Novu Dashboard at http://localhost:14200
2. Create account and get API key
3. Set `NOVU_API_KEY` in `.env` or docker-compose
4. Create workflows for each event type (PGR_CREATED, etc.)

## Design Documents

- [HLD.md](./HLD.md) - High Level Design
- [WhatsAppDesign.md](./WhatsAppDesign.md) - Detailed Implementation Spec
- [API specifications/](./API%20specifications/) - OpenAPI specs
- [ER diagrams/](./ER%20diagrams/) - Database schemas
- [Sequence Diagrams/](./Sequence%20Diagrams/) - Flow diagrams
