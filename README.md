# DIGIT WhatsApp Notification Services

Outbound WhatsApp notification system for DIGIT platform using Novu for orchestration and Baileys for WhatsApp Web API.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Services](#services)
- [Setup Instructions](#setup-instructions)
- [Configuration](#configuration)
- [API Reference](#api-reference)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)

## Prerequisites

- **Docker** (20.10+) and **Docker Compose** (v2+)
- **Tilt** (for local development with hot-reload)
- **Node.js** (18+) - only if running services outside Docker
- **Git**

### Install Tilt (macOS/Linux)

```bash
curl -fsSL https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh | bash
```

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/ChakshuGautam/digit-bidirectional-wa.git
cd digit-bidirectional-wa

# 2. Create environment file
cp .env.example .env

# 3. Start all services with Docker Compose
docker compose up -d

# 4. (Optional) Start Tilt for hot-reload development
tilt up

# 5. Seed initial configs
./seed-configs.sh

# 6. Connect WhatsApp - Open in browser:
#    http://localhost:18203/baileys/qr/page
#    Scan QR code with WhatsApp mobile app

# 7. Run E2E tests to verify setup
./scripts/e2e-tests.sh

# 8. Test sending a notification
curl -X POST http://localhost:18202/novu-bridge/v1/_trigger \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "PGR_CREATE",
    "tenantId": "pg.citya",
    "recipient": {"phone": "919876543210"},
    "data": {
      "serviceRequestId": "PGR-2026-00001",
      "serviceCode": "StreetLight",
      "address": "Main Road"
    }
  }'
```

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   PGR Service   │────▶│     Kafka        │────▶│  Novu Bridge    │
│  (DIGIT Core)   │     │   (Events)       │     │ (Orchestrator)  │
└─────────────────┘     └──────────────────┘     └────────┬────────┘
                                                          │
              ┌───────────────────────────────────────────┼───────────────────┐
              │                                           │                   │
              ▼                                           ▼                   ▼
      ┌───────────────┐                        ┌──────────────────┐   ┌─────────────┐
      │ Config Service│                        │ User Preferences │   │   Baileys   │
      │  (Templates)  │                        │    (Consent)     │   │ (WhatsApp)  │
      └───────────────┘                        └──────────────────┘   └─────────────┘
```

### Notification Flow (11 Steps)

1. **Parse Event** - Receive from Kafka or manual trigger
2. **Check Channel Enablement** - Is WhatsApp enabled for this event?
3. **Check Feature Flag** - Is WhatsApp outbound globally enabled?
4. **Check Quiet Hours** - Defer if within quiet hours
5. **Rate Limiting** - Prevent spam
6. **Check User Consent** - User must have granted WhatsApp consent
7. **Resolve Language** - Get user's preferred language
8. **Get Template Binding** - Map event to template
9. **Fetch Template** - Get localized template content
10. **Render Message** - Apply Handlebars templating
11. **Send via Baileys** - Deliver to WhatsApp

## Services

| Service | Port | Description |
|---------|------|-------------|
| **digit-novu-bridge** | 18202 | Kafka consumer, notification orchestration |
| **digit-config-service** | 18201 | Templates, policies, event-channel mappings |
| **digit-user-preferences** | 18200 | User consent and language preferences |
| **baileys-provider** | 18203 | WhatsApp Web API via Baileys |

### Infrastructure Services

| Service | Port | Description |
|---------|------|-------------|
| Postgres | 15432 | Database for configs and preferences |
| Redis | 16379 | Caching |
| Kafka | 19092 | Event streaming |
| Kong | 18000 | API Gateway |
| Novu API | 13000 | Notification orchestration API |
| Novu Dashboard | 14200 | Novu web UI |

## Setup Instructions

### Step 1: Environment Configuration

```bash
cp .env.example .env
```

Edit `.env` as needed:

```bash
# Novu API Key (get from Novu dashboard after first login)
NOVU_API_KEY=your-api-key-here

# Notification mode
USE_NOVU_TEMPLATES=false  # Use config service templates
USE_BAILEYS=true          # Send via Baileys (local dev)

# Baileys mode
MOCK_MODE=false           # Set true to log messages without sending
```

### Step 2: Start Services

**Option A: Docker Compose only**
```bash
docker compose up -d
```

**Option B: Docker Compose + Tilt (recommended for development)**
```bash
docker compose up -d
tilt up
```

Tilt provides:
- Hot-reload for all TypeScript services
- Unified dashboard at http://localhost:10350
- Health monitoring
- One-click service restarts

### Step 3: Seed Configuration Data

```bash
./seed-configs.sh
```

This creates:
- Event-to-channel mappings (EVENT_CHANNELS)
- Feature flags (FEATURE_FLAGS)
- Delivery guardrails (rate limits, quiet hours)
- Template bindings
- PGR notification templates

### Step 4: Connect WhatsApp

1. Open http://localhost:18203/baileys/qr/page
2. On your phone: WhatsApp → Settings → Linked Devices → Link a Device
3. Scan the QR code
4. Wait for "Connected" message

The session is persisted - you won't need to re-scan after restarts.

### Step 5: Create Test User with Consent

```bash
curl -X POST http://localhost:18200/user-preferences/v1/_upsert \
  -H "Content-Type: application/json" \
  -d '{
    "preference": {
      "userId": "test-user",
      "tenantId": "pg.citya",
      "preferenceCode": "USER_NOTIFICATION_PREFERENCES",
      "payload": {
        "preferredLanguage": "en_IN",
        "consent": {
          "WHATSAPP": {
            "status": "GRANTED",
            "grantedAt": "2026-01-01T00:00:00.000Z",
            "method": "explicit"
          }
        },
        "channels": {
          "WHATSAPP": {"enabled": true, "phone": "919876543210"}
        }
      }
    }
  }'
```

### Step 6: Verify Setup

```bash
# Run E2E tests
./scripts/e2e-tests.sh

# Expected: All 16 tests pass
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `USE_BAILEYS` | `true` | Use Baileys for WhatsApp delivery |
| `USE_NOVU_TEMPLATES` | `false` | Use Novu for template management |
| `MOCK_MODE` | `false` | Log messages without sending |
| `NOVU_API_KEY` | - | Novu API key (required for Novu mode) |
| `KAFKA_BROKERS` | `kafka:9092` | Kafka broker addresses |
| `KAFKA_TOPICS` | `pgr-create,pgr-update` | Topics to consume |

### Kong API Gateway

All services are exposed through Kong at port 18000:

| Path | Service | Auth Required |
|------|---------|---------------|
| `/baileys/*` | Baileys Provider | Yes (X-API-Key) |
| `/novu-bridge/*` | Novu Bridge | Yes |
| `/user-preferences/*` | User Preferences | Yes |
| `/notification-config/*` | Config Service | Yes |
| `/baileys/qr/*` | QR Code Pages | No |
| `/baileys/health` | Health Check | No |

**API Key:** `digit-dev-api-key-change-me` (change in production!)

## API Reference

### Health Checks

```bash
# All services
curl http://localhost:18200/user-preferences/health
curl http://localhost:18201/configs/health
curl http://localhost:18202/novu-bridge/health
curl http://localhost:18203/baileys/health
```

### User Preferences

```bash
# Create/Update user preference
curl -X POST http://localhost:18200/user-preferences/v1/_upsert \
  -H "Content-Type: application/json" \
  -d '{
    "preference": {
      "userId": "user-123",
      "tenantId": "pg.citya",
      "preferenceCode": "USER_NOTIFICATION_PREFERENCES",
      "payload": {
        "preferredLanguage": "en_IN",
        "consent": {
          "WHATSAPP": {"status": "GRANTED"}
        }
      }
    }
  }'

# Search preferences
curl -X POST http://localhost:18200/user-preferences/v1/_search \
  -H "Content-Type: application/json" \
  -d '{"criteria": {"userId": "user-123", "tenantId": "pg.citya"}}'
```

### Config Service

```bash
# Create config
curl -X POST http://localhost:18201/configs/v1/_create \
  -H "Content-Type: application/json" \
  -d '{
    "config": {
      "tenantId": "pg.citya",
      "namespace": "notification-orchestrator",
      "configName": "My Template",
      "configCode": "TEMPLATE_CUSTOM",
      "content": {"templates": {"en_IN": "Hello {{name}}!"}}
    }
  }'

# Search configs
curl -X POST http://localhost:18201/configs/v1/_search \
  -H "Content-Type: application/json" \
  -d '{"criteria": {"tenantId": "pg.citya", "namespace": "notification-orchestrator"}}'
```

### Trigger Notification

```bash
curl -X POST http://localhost:18202/novu-bridge/v1/_trigger \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "PGR_CREATE",
    "tenantId": "pg.citya",
    "recipient": {
      "userId": "user-123",
      "phone": "919876543210"
    },
    "data": {
      "serviceRequestId": "PGR-2026-00001",
      "serviceCode": "StreetLight",
      "address": "Main Road, City Center",
      "createdTime": "2026-01-15 10:30 AM"
    }
  }'
```

### Baileys Provider

```bash
# Check WhatsApp status
curl http://localhost:18203/baileys/status

# Send direct message
curl -X POST http://localhost:18203/baileys/send \
  -H "Content-Type: application/json" \
  -d '{"to": "919876543210", "content": "Hello from DIGIT!"}'

# Disconnect WhatsApp
curl -X POST http://localhost:18203/baileys/disconnect

# Reconnect
curl -X POST http://localhost:18203/baileys/reconnect
```

## Testing

### Run E2E Tests

```bash
# Direct service access
./scripts/e2e-tests.sh

# Through Kong gateway
./scripts/e2e-tests.sh --via-kong
```

### Test Coverage

| Section | Tests |
|---------|-------|
| Health Checks | 4 tests |
| Config Service | 3 tests |
| User Preferences | 3 tests |
| Baileys Provider | 3 tests |
| Novu Bridge | 3 tests |
| **Total** | **16 tests** |

### Manual Testing

```bash
# 1. Check all services are healthy
curl http://localhost:18202/novu-bridge/health

# 2. Create a user with consent
# (see Step 5 above)

# 3. Trigger a notification
curl -X POST http://localhost:18202/novu-bridge/v1/_trigger \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "PGR_CREATE",
    "tenantId": "pg.citya",
    "recipient": {"phone": "YOUR_PHONE_NUMBER"},
    "data": {"serviceRequestId": "TEST-001", "serviceCode": "Test"}
  }'

# 4. Check your WhatsApp for the message!
```

## Troubleshooting

### WhatsApp Not Connecting

```bash
# Check Baileys logs
docker logs baileys-provider -f

# Common issues:
# - QR code expired: Refresh the QR page
# - Session corrupted: Delete auth_info volume and reconnect
docker compose down
docker volume rm digit-bidirectional-wa_baileys_auth
docker compose up -d
```

### Notification Not Sending

```bash
# Check novu-bridge logs
docker logs digit-novu-bridge -f

# Common issues:
# - User consent not granted: Create preference with WHATSAPP.status = "GRANTED"
# - Event not enabled: Check EVENT_CHANNELS config
# - Template not found: Run seed-configs.sh
```

### Services Not Starting

```bash
# Check all container status
docker compose ps

# View logs for specific service
docker compose logs -f digit-config-service

# Restart all services
docker compose restart
```

### Database Issues

```bash
# Connect to Postgres
docker exec -it docker-postgres psql -U egov -d egov

# Check tables
\dt

# View configs
SELECT * FROM notification_configs LIMIT 5;
```

## Design Documents

- [HLD.md](./HLD.md) - High Level Design
- [WhatsAppDesign.md](./WhatsAppDesign.md) - Detailed Implementation Spec
- [API specifications/](./API%20specifications/) - OpenAPI specs
- [ER diagrams/](./ER%20diagrams/) - Database schemas
- [Sequence Diagrams/](./Sequence%20Diagrams/) - Flow diagrams

## License

MIT
