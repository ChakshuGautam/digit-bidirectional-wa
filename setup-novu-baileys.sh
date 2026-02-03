#!/bin/bash
# Setup Novu with Baileys Chat Webhook Provider
# Run this after getting your API key from Novu dashboard

set -e

NOVU_API_URL="http://localhost:13000"
BAILEYS_WEBHOOK_URL="http://baileys-provider:8203/baileys/novu-webhook"

# Check if API key provided
if [ -z "$NOVU_API_KEY" ]; then
  echo "============================================"
  echo "Novu + Baileys Setup"
  echo "============================================"
  echo ""
  echo "1. Open Novu Dashboard: http://localhost:14200"
  echo "2. Create account (or login)"
  echo "3. Go to Settings > API Keys"
  echo "4. Copy your API key"
  echo "5. Run: NOVU_API_KEY=your-key ./setup-novu-baileys.sh"
  echo ""
  exit 1
fi

echo "Setting up Novu with Baileys provider..."

# Step 1: Get current environment
echo "Step 1: Getting environment info..."
ENV_INFO=$(curl -s -H "Authorization: ApiKey $NOVU_API_KEY" \
  "$NOVU_API_URL/v1/environments/me")
echo "Environment: $(echo $ENV_INFO | jq -r '.data.name // "default"')"

# Step 2: Create/Update Chat Webhook integration (for WhatsApp via Baileys)
echo "Step 2: Setting up Chat Webhook integration for Baileys..."

# First check existing integrations
EXISTING=$(curl -s -H "Authorization: ApiKey $NOVU_API_KEY" \
  "$NOVU_API_URL/v1/integrations" | jq -r '.data[] | select(.providerId == "chat-webhook") | .id')

if [ -n "$EXISTING" ]; then
  echo "  Updating existing chat-webhook integration..."
  curl -s -X PUT -H "Authorization: ApiKey $NOVU_API_KEY" \
    -H "Content-Type: application/json" \
    "$NOVU_API_URL/v1/integrations/$EXISTING" \
    -d '{
      "active": true,
      "credentials": {},
      "check": false
    }' | jq '.data.id'
else
  echo "  Creating new chat-webhook integration..."
  curl -s -X POST -H "Authorization: ApiKey $NOVU_API_KEY" \
    -H "Content-Type: application/json" \
    "$NOVU_API_URL/v1/integrations" \
    -d '{
      "providerId": "chat-webhook",
      "channel": "chat",
      "active": true,
      "credentials": {},
      "check": false
    }' | jq '.data.id'
fi

# Step 3: Create PGR_CREATED workflow
echo "Step 3: Creating PGR_CREATED workflow..."

curl -s -X POST -H "Authorization: ApiKey $NOVU_API_KEY" \
  -H "Content-Type: application/json" \
  "$NOVU_API_URL/v1/notification-templates" \
  -d '{
    "name": "PGR Complaint Created",
    "notificationGroupId": "",
    "tags": ["pgr", "whatsapp"],
    "description": "Notification sent when a new PGR complaint is registered",
    "steps": [
      {
        "template": {
          "type": "chat",
          "content": "*DIGIT Municipal Services*\n\n📋 *New Complaint Registered*\n\nYour complaint has been successfully registered.\n\n*Complaint No:* {{serviceRequestId}}\n*Type:* {{serviceCode}}\n*Location:* {{address}}\n*Status:* 🔵 Open\n\n*Filed On:* {{createdTime}}\n\nYou will receive updates on your complaint status.\n\nThank you for using DIGIT services."
        },
        "active": true
      }
    ],
    "active": true,
    "critical": false,
    "preferenceSettings": {
      "email": false,
      "sms": false,
      "in_app": false,
      "chat": true,
      "push": false
    }
  }' | jq '{id: .data._id, name: .data.name, triggers: .data.triggers}'

# Step 4: Create PGR_STATUS_CHANGE workflow
echo "Step 4: Creating PGR_STATUS_CHANGE workflow..."

curl -s -X POST -H "Authorization: ApiKey $NOVU_API_KEY" \
  -H "Content-Type: application/json" \
  "$NOVU_API_URL/v1/notification-templates" \
  -d '{
    "name": "PGR Status Changed",
    "tags": ["pgr", "whatsapp"],
    "description": "Notification sent when PGR complaint status changes",
    "steps": [
      {
        "template": {
          "type": "chat",
          "content": "*DIGIT Municipal Services*\n\n📋 *Complaint Status Update*\n\nYour complaint status has been updated.\n\n*Complaint No:* {{serviceRequestId}}\n*Type:* {{serviceCode}}\n*Previous Status:* {{previousStatus}}\n*Current Status:* {{status}}\n\n{{#if comment}}*Comment:* {{comment}}{{/if}}\n\n*Updated On:* {{updatedTime}}\n\nThank you for using DIGIT services."
        },
        "active": true
      }
    ],
    "active": true,
    "critical": false,
    "preferenceSettings": {
      "email": false,
      "sms": false,
      "in_app": false,
      "chat": true,
      "push": false
    }
  }' | jq '{id: .data._id, name: .data.name, triggers: .data.triggers}'

# Step 5: Create PGR_RESOLVED workflow
echo "Step 5: Creating PGR_RESOLVED workflow..."

curl -s -X POST -H "Authorization: ApiKey $NOVU_API_KEY" \
  -H "Content-Type: application/json" \
  "$NOVU_API_URL/v1/notification-templates" \
  -d '{
    "name": "PGR Complaint Resolved",
    "tags": ["pgr", "whatsapp"],
    "description": "Notification sent when PGR complaint is resolved",
    "steps": [
      {
        "template": {
          "type": "chat",
          "content": "*DIGIT Municipal Services*\n\n📋 *Complaint Resolved*\n\nYour complaint has been resolved.\n\n*Complaint No:* {{serviceRequestId}}\n*Type:* {{serviceCode}}\n*Location:* {{address}}\n*Status:* ✅ Resolved\n\n*Resolution:* {{resolution}}\n\n*Resolved On:* {{resolvedTime}}\n*Resolved By:* {{resolvedBy}}\n\nThank you for using DIGIT services.\n\n---\nRate this service: {{ratingUrl}}"
        },
        "active": true
      }
    ],
    "active": true,
    "critical": false,
    "preferenceSettings": {
      "email": false,
      "sms": false,
      "in_app": false,
      "chat": true,
      "push": false
    }
  }' | jq '{id: .data._id, name: .data.name, triggers: .data.triggers}'

echo ""
echo "============================================"
echo "Setup Complete!"
echo "============================================"
echo ""
echo "Workflows created in Novu:"
echo "  - pgr-complaint-created"
echo "  - pgr-status-changed"
echo "  - pgr-complaint-resolved"
echo ""
echo "Next steps:"
echo "1. Update docker-compose.yml with NOVU_API_KEY=$NOVU_API_KEY"
echo "2. Restart digit-novu-bridge"
echo "3. Test: curl -X POST http://localhost:18202/novu-bridge/v1/_trigger ..."
echo ""
