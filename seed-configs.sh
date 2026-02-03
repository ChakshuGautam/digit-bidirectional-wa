#!/bin/bash
# Seed initial notification configs for WhatsApp integration
# Run after services are healthy: ./whatsapp/seed-configs.sh

CONFIG_URL="${CONFIG_URL:-http://localhost:18201}"
USER_PREFS_URL="${USER_PREFS_URL:-http://localhost:18200}"
TENANT_ID="${TENANT_ID:-pg.citya}"

echo "Seeding configs to $CONFIG_URL for tenant $TENANT_ID..."

# 1. Feature Flags
curl -s -X POST "$CONFIG_URL/configs/v1/_create" \
  -H "Content-Type: application/json" \
  -d '{
    "requestInfo": {},
    "config": {
      "tenantId": "'$TENANT_ID'",
      "namespace": "notification-orchestrator",
      "configName": "Feature Flags",
      "configCode": "FEATURE_FLAGS",
      "version": "1.0.0",
      "status": "ACTIVE",
      "content": {
        "WHATSAPP_OUTBOUND_ENABLED": true,
        "SMS_OUTBOUND_ENABLED": false,
        "EMAIL_OUTBOUND_ENABLED": false
      }
    }
  }' | jq -r '.configs[0].configCode // .errors[0].message'

# 2. Event Channels
curl -s -X POST "$CONFIG_URL/configs/v1/_create" \
  -H "Content-Type: application/json" \
  -d '{
    "requestInfo": {},
    "config": {
      "tenantId": "'$TENANT_ID'",
      "namespace": "notification-orchestrator",
      "configName": "Event Channel Routing",
      "configCode": "EVENT_CHANNELS",
      "version": "1.0.0",
      "status": "ACTIVE",
      "content": {
        "events": {
          "PGR_CREATED": { "channels": ["WHATSAPP"], "exemptFromQuietHours": false },
          "PGR_UPDATED": { "channels": ["WHATSAPP"], "exemptFromQuietHours": false },
          "PGR_STATUS_CHANGE": { "channels": ["WHATSAPP"], "exemptFromQuietHours": true },
          "PGR_RESOLVED": { "channels": ["WHATSAPP"], "exemptFromQuietHours": true }
        }
      }
    }
  }' | jq -r '.configs[0].configCode // .errors[0].message'

# 3. Delivery Guardrails
curl -s -X POST "$CONFIG_URL/configs/v1/_create" \
  -H "Content-Type: application/json" \
  -d '{
    "requestInfo": {},
    "config": {
      "tenantId": "'$TENANT_ID'",
      "namespace": "notification-orchestrator",
      "configName": "Delivery Guardrails",
      "configCode": "DELIVERY_GUARDRAILS",
      "version": "1.0.0",
      "status": "ACTIVE",
      "content": {
        "quietHours": { "start": 22, "end": 7 },
        "rateLimits": {
          "PGR_CREATED": { "maxPerHour": 100 },
          "PGR_UPDATED": { "maxPerHour": 200 },
          "PGR_STATUS_CHANGE": { "maxPerHour": 500 },
          "default": { "maxPerHour": 100 }
        },
        "retryPolicy": {
          "maxRetries": 3,
          "backoffMs": [1000, 5000, 30000]
        }
      }
    }
  }' | jq -r '.configs[0].configCode // .errors[0].message'

# 4. Language Strategy
curl -s -X POST "$CONFIG_URL/configs/v1/_create" \
  -H "Content-Type: application/json" \
  -d '{
    "requestInfo": {},
    "config": {
      "tenantId": "'$TENANT_ID'",
      "namespace": "notification-orchestrator",
      "configName": "Language Resolution Strategy",
      "configCode": "LANGUAGE_STRATEGY",
      "version": "1.0.0",
      "status": "ACTIVE",
      "content": {
        "defaultLocale": "en_IN",
        "supportedLocales": ["en_IN", "hi_IN", "kn_IN", "ta_IN"],
        "fallbackChain": ["user_preference", "tenant_default", "system_default"]
      }
    }
  }' | jq -r '.configs[0].configCode // .errors[0].message'

# 5. Template Bindings
curl -s -X POST "$CONFIG_URL/configs/v1/_create" \
  -H "Content-Type: application/json" \
  -d '{
    "requestInfo": {},
    "config": {
      "tenantId": "'$TENANT_ID'",
      "namespace": "notification-orchestrator",
      "configName": "Template Bindings",
      "configCode": "TEMPLATE_BINDINGS",
      "version": "1.0.0",
      "status": "ACTIVE",
      "content": {
        "bindings": [
          { "eventType": "PGR_CREATED", "channel": "WHATSAPP", "templateCode": "TEMPLATE_PGR_CREATED" },
          { "eventType": "PGR_UPDATED", "channel": "WHATSAPP", "templateCode": "TEMPLATE_PGR_UPDATED" },
          { "eventType": "PGR_STATUS_CHANGE", "channel": "WHATSAPP", "templateCode": "TEMPLATE_PGR_STATUS" },
          { "eventType": "PGR_RESOLVED", "channel": "WHATSAPP", "templateCode": "TEMPLATE_PGR_RESOLVED" }
        ]
      }
    }
  }' | jq -r '.configs[0].configCode // .errors[0].message'

# 6. PGR Created Template
curl -s -X POST "$CONFIG_URL/configs/v1/_create" \
  -H "Content-Type: application/json" \
  -d '{
    "requestInfo": {},
    "config": {
      "tenantId": "'$TENANT_ID'",
      "namespace": "notification-orchestrator",
      "configName": "PGR Created Template",
      "configCode": "TEMPLATE_PGR_CREATED",
      "version": "1.0.0",
      "status": "ACTIVE",
      "content": {
        "templates": {
          "en_IN": "Your complaint {{complaintNumber}} for \"{{complaintType}}\" has been registered successfully. You will receive updates on this number. Track: {{trackingUrl}}",
          "hi_IN": "आपकी शिकायत {{complaintNumber}} \"{{complaintType}}\" के लिए सफलतापूर्वक दर्ज हो गई है। आपको इस नंबर पर अपडेट मिलेंगे। ट्रैक करें: {{trackingUrl}}"
        }
      }
    }
  }' | jq -r '.configs[0].configCode // .errors[0].message'

# 7. PGR Updated Template
curl -s -X POST "$CONFIG_URL/configs/v1/_create" \
  -H "Content-Type: application/json" \
  -d '{
    "requestInfo": {},
    "config": {
      "tenantId": "'$TENANT_ID'",
      "namespace": "notification-orchestrator",
      "configName": "PGR Updated Template",
      "configCode": "TEMPLATE_PGR_UPDATED",
      "version": "1.0.0",
      "status": "ACTIVE",
      "content": {
        "templates": {
          "en_IN": "Your complaint {{complaintNumber}} has been updated. New details: {{updateSummary}}. Track: {{trackingUrl}}",
          "hi_IN": "आपकी शिकायत {{complaintNumber}} अपडेट की गई है। नई जानकारी: {{updateSummary}}। ट्रैक करें: {{trackingUrl}}"
        }
      }
    }
  }' | jq -r '.configs[0].configCode // .errors[0].message'

# 8. PGR Status Change Template
curl -s -X POST "$CONFIG_URL/configs/v1/_create" \
  -H "Content-Type: application/json" \
  -d '{
    "requestInfo": {},
    "config": {
      "tenantId": "'$TENANT_ID'",
      "namespace": "notification-orchestrator",
      "configName": "PGR Status Change Template",
      "configCode": "TEMPLATE_PGR_STATUS",
      "version": "1.0.0",
      "status": "ACTIVE",
      "content": {
        "templates": {
          "en_IN": "Status update for complaint {{complaintNumber}}: {{oldStatus}} → {{newStatus}}. {{statusMessage}} Track: {{trackingUrl}}",
          "hi_IN": "शिकायत {{complaintNumber}} की स्थिति: {{oldStatus}} → {{newStatus}}। {{statusMessage}} ट्रैक करें: {{trackingUrl}}"
        }
      }
    }
  }' | jq -r '.configs[0].configCode // .errors[0].message'

# 9. PGR Resolved Template
curl -s -X POST "$CONFIG_URL/configs/v1/_create" \
  -H "Content-Type: application/json" \
  -d '{
    "requestInfo": {},
    "config": {
      "tenantId": "'$TENANT_ID'",
      "namespace": "notification-orchestrator",
      "configName": "PGR Resolved Template",
      "configCode": "TEMPLATE_PGR_RESOLVED",
      "version": "1.0.0",
      "status": "ACTIVE",
      "content": {
        "templates": {
          "en_IN": "Great news! Your complaint {{complaintNumber}} has been resolved. Resolution: {{resolution}}. Please rate your experience: {{feedbackUrl}}",
          "hi_IN": "खुशखबरी! आपकी शिकायत {{complaintNumber}} का समाधान हो गया है। समाधान: {{resolution}}। कृपया अपना अनुभव साझा करें: {{feedbackUrl}}"
        }
      }
    }
  }' | jq -r '.configs[0].configCode // .errors[0].message'

echo ""
echo "Config seeding complete!"
echo ""
echo "Creating test user preference..."

# Create a test user with WhatsApp consent
curl -s -X POST "$USER_PREFS_URL/user-preferences/v1/_upsert" \
  -H "Content-Type: application/json" \
  -d '{
    "requestInfo": {},
    "preference": {
      "userId": "test-user-001",
      "tenantId": "'$TENANT_ID'",
      "preferenceCode": "USER_NOTIFICATION_PREFERENCES",
      "payload": {
        "preferredLanguage": "en_IN",
        "consent": {
          "WHATSAPP": { "status": "GRANTED", "scope": "GLOBAL" },
          "SMS": { "status": "REVOKED", "scope": "GLOBAL" },
          "EMAIL": { "status": "GRANTED", "scope": "GLOBAL" }
        }
      }
    }
  }' | jq -r '.preferences[0].userId // .errors[0].message'

echo ""
echo "Done! Test the notification flow with:"
echo ""
echo 'curl -X POST http://localhost:18202/novu-bridge/v1/_trigger \'
echo '  -H "Content-Type: application/json" \'
echo '  -d '"'"'{
    "eventType": "PGR_CREATED",
    "tenantId": "pg.citya",
    "recipient": { "userId": "test-user-001", "phone": "+919876543210" },
    "data": {
      "complaintNumber": "PGR-2026-001234",
      "complaintType": "Street Light Not Working",
      "trackingUrl": "https://pgr.example.com/track/001234"
    }
  }'"'"
