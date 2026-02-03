import express from 'express';
import { Kafka, Consumer, EachMessagePayload } from 'kafkajs';
import { Novu } from '@novu/node';
import Handlebars from 'handlebars';
import { v4 as uuidv4 } from 'uuid';

const app = express();
app.use(express.json());

const PORT = process.env.SERVER_PORT || 8202;

// Configuration
const CONFIG_SERVICE_URL = process.env.CONFIG_SERVICE_URL || 'http://digit-config-service:8201';
const USER_PREFS_URL = process.env.USER_PREFERENCES_URL || 'http://digit-user-preferences:8200';
const NOVU_API_KEY = process.env.NOVU_API_KEY || '';
const KAFKA_BROKERS = (process.env.KAFKA_BROKERS || 'kafka:9092').split(',');
const KAFKA_GROUP_ID = process.env.KAFKA_GROUP_ID || 'digit-novu-bridge';
const KAFKA_TOPICS = (process.env.KAFKA_TOPICS || 'pgr-create,pgr-update').split(',');

// Baileys provider for local testing
const BAILEYS_PROVIDER_URL = process.env.BAILEYS_PROVIDER_URL || 'http://baileys-provider:8203';
const USE_BAILEYS = process.env.USE_BAILEYS === 'true';
// When using Novu, let Novu manage templates (don't pre-render)
const USE_NOVU_TEMPLATES = process.env.USE_NOVU_TEMPLATES === 'true';
// Local Novu API endpoint (for self-hosted Novu)
const NOVU_API_URL = process.env.NOVU_API_URL || 'http://novu-api:3000';

// Novu client (initialized if API key provided)
let novu: Novu | null = null;
if (NOVU_API_KEY) {
  novu = new Novu(NOVU_API_KEY, {
    backendUrl: NOVU_API_URL
  });
}

// Map event types to Novu workflow identifiers
const NOVU_WORKFLOW_MAP: Record<string, string> = {
  'PGR_CREATE': 'pgr-complaint-created',
  'PGR_CREATED': 'pgr-complaint-created',
  'PGR_UPDATE': 'pgr-status-changed',
  'PGR_STATUS_CHANGE': 'pgr-status-changed',
  'PGR_RESOLVED': 'pgr-complaint-resolved'
};

// Kafka client
const kafka = new Kafka({
  clientId: 'digit-novu-bridge',
  brokers: KAFKA_BROKERS,
  retry: { retries: 5 }
});

let consumer: Consumer | null = null;

// In-memory cache for rate limiting
const rateLimitCache = new Map<string, { count: number; resetTime: number }>();

// Health check
app.get('/novu-bridge/health', (req, res) => {
  res.json({
    status: 'UP',
    service: 'digit-novu-bridge',
    kafka: consumer ? 'connected' : 'disconnected',
    novu: novu ? 'configured' : 'not configured',
    mode: USE_NOVU_TEMPLATES ? 'novu-templates' : (USE_BAILEYS ? 'baileys-direct' : 'legacy'),
    baileysUrl: USE_BAILEYS ? BAILEYS_PROVIDER_URL : null
  });
});

app.get('/novu-bridge/actuator/health', (req, res) => {
  res.json({ status: 'UP' });
});

// Manual trigger endpoint for testing
app.post('/novu-bridge/v1/_trigger', async (req, res) => {
  try {
    const { eventType, tenantId, recipient, data } = req.body;

    const result = await processNotification({
      eventType,
      tenantId,
      recipient,
      data
    });

    res.json({
      responseInfo: { status: 'successful' },
      result
    });
  } catch (error) {
    console.error('Manual trigger error:', error);
    res.status(500).json({
      responseInfo: { status: 'failed' },
      errors: [{ code: 'TRIGGER_FAILED', message: String(error) }]
    });
  }
});

// Core notification processing (11-step flow from design doc)
async function processNotification(event: {
  eventType: string;
  tenantId: string;
  recipient: { userId?: string; phone?: string };
  data: Record<string, any>;
}): Promise<{ status: string; transactionId: string; details?: any }> {
  const transactionId = `${event.eventType}-WHATSAPP-${event.recipient.userId || event.recipient.phone}-${Date.now()}`;
  console.log(`[${transactionId}] Processing notification...`);

  try {
    // Step 1: Parse event
    const { eventType, tenantId, recipient, data } = event;
    console.log(`[${transactionId}] Step 1: Event parsed - ${eventType} for ${tenantId}`);

    // Step 2: Check event-to-WhatsApp enablement
    const eventChannels = await fetchConfig(tenantId, 'notification-orchestrator', 'EVENT_CHANNELS');
    const channelConfig = eventChannels?.content?.events?.[eventType];
    if (!channelConfig?.channels?.includes('WHATSAPP')) {
      return { status: 'SKIPPED', transactionId, details: 'WhatsApp not enabled for this event' };
    }
    console.log(`[${transactionId}] Step 2: WhatsApp enabled for event`);

    // Step 3: Check feature flag
    const featureFlags = await fetchConfig(tenantId, 'notification-orchestrator', 'FEATURE_FLAGS');
    if (!featureFlags?.content?.WHATSAPP_OUTBOUND_ENABLED) {
      return { status: 'SKIPPED', transactionId, details: 'WhatsApp outbound disabled' };
    }
    console.log(`[${transactionId}] Step 3: Feature flag enabled`);

    // Step 4: Check quiet hours
    const guardrails = await fetchConfig(tenantId, 'notification-orchestrator', 'DELIVERY_GUARDRAILS');
    const quietHours = guardrails?.content?.quietHours;
    if (quietHours && !channelConfig?.exemptFromQuietHours) {
      const now = new Date();
      const hour = now.getHours();
      if (hour >= quietHours.start || hour < quietHours.end) {
        return { status: 'DEFERRED', transactionId, details: 'Quiet hours - will retry later' };
      }
    }
    console.log(`[${transactionId}] Step 4: Not in quiet hours`);

    // Step 5: Rate limiting
    const rateLimitKey = `${tenantId}-${eventType}-WHATSAPP`;
    const rateLimit = guardrails?.content?.rateLimits?.[eventType] || { maxPerHour: 100 };
    const now = Date.now();
    const cached = rateLimitCache.get(rateLimitKey);

    if (cached && cached.resetTime > now && cached.count >= rateLimit.maxPerHour) {
      return { status: 'RATE_LIMITED', transactionId, details: 'Rate limit exceeded' };
    }

    if (!cached || cached.resetTime <= now) {
      rateLimitCache.set(rateLimitKey, { count: 1, resetTime: now + 3600000 });
    } else {
      cached.count++;
    }
    console.log(`[${transactionId}] Step 5: Rate limit check passed`);

    // Step 6: Check user consent
    const userPrefs = await fetchUserPreferences(recipient.userId || recipient.phone!, tenantId);
    const consent = userPrefs?.payload?.consent?.WHATSAPP;
    if (consent?.status !== 'GRANTED') {
      return { status: 'SKIPPED', transactionId, details: 'User has not granted WhatsApp consent' };
    }
    console.log(`[${transactionId}] Step 6: User consent verified`);

    // Step 7: Resolve language
    const langStrategy = await fetchConfig(tenantId, 'notification-orchestrator', 'LANGUAGE_STRATEGY');
    let locale = userPrefs?.payload?.preferredLanguage || langStrategy?.content?.defaultLocale || 'en_IN';
    console.log(`[${transactionId}] Step 7: Language resolved - ${locale}`);

    // NOVU TEMPLATE MODE: Let Novu manage templates and rendering
    if (USE_NOVU_TEMPLATES && novu) {
      const workflowId = NOVU_WORKFLOW_MAP[eventType];
      if (!workflowId) {
        return { status: 'ERROR', transactionId, details: `No Novu workflow mapped for event: ${eventType}` };
      }

      const phone = recipient.phone || normalizePhone(recipient.userId!);
      const subscriberId = `phone_${phone.replace(/\D/g, '')}`;

      console.log(`[${transactionId}] Step 8-10: Using Novu templates (workflow: ${workflowId})`);

      // Ensure subscriber exists with phone number and chat credentials
      try {
        await novu.subscribers.identify(subscriberId, {
          phone,
          data: { phoneNumber: phone }
        });
        // Set chat-webhook credentials for this subscriber
        await novu.subscribers.setCredentials(subscriberId, 'chat-webhook', {
          webhookUrl: `${BAILEYS_PROVIDER_URL}/baileys/novu-webhook`
        });
        console.log(`[${transactionId}] Subscriber ${subscriberId} configured with chat-webhook`);
      } catch (e) {
        console.warn(`[${transactionId}] Subscriber setup warning:`, e);
      }

      // Trigger Novu workflow with raw data (Novu handles template rendering)
      await novu.trigger(workflowId, {
        to: {
          subscriberId,
          phone
        },
        payload: {
          ...data,
          phoneNumber: phone,
          locale
        },
        transactionId
      });

      console.log(`[${transactionId}] Step 11: Novu workflow '${workflowId}' triggered`);
      return { status: 'SENT', transactionId, details: { workflow: workflowId, provider: 'novu', subscriberId } };
    }

    // LEGACY MODE: Bridge manages templates (USE_BAILEYS or fallback)
    // Step 8: Get template binding
    const templateBindings = await fetchConfig(tenantId, 'notification-orchestrator', 'TEMPLATE_BINDINGS');
    const binding = templateBindings?.content?.bindings?.find(
      (b: any) => b.eventType === eventType && b.channel === 'WHATSAPP'
    );
    if (!binding) {
      return { status: 'ERROR', transactionId, details: 'No template binding found for event' };
    }
    console.log(`[${transactionId}] Step 8: Template binding found - ${binding.templateCode}`);

    // Step 9: Fetch template content
    const template = await fetchConfig(tenantId, 'notification-orchestrator', binding.templateCode);
    const templateText = template?.content?.templates?.[locale] || template?.content?.templates?.['en_IN'];
    if (!templateText) {
      return { status: 'ERROR', transactionId, details: 'Template content not found' };
    }
    console.log(`[${transactionId}] Step 9: Template retrieved`);

    // Step 10: Render message
    const compiled = Handlebars.compile(templateText);
    const renderedMessage = compiled(data);
    console.log(`[${transactionId}] Step 10: Message rendered`);

    // Step 11: Send message via Baileys (legacy mode)
    if (USE_BAILEYS) {
      // Use Baileys provider for local testing
      const phone = recipient.phone || normalizePhone(recipient.userId!);
      console.log(`[${transactionId}] Step 11: Sending via Baileys to ${phone}`);

      const baileysResponse = await fetch(`${BAILEYS_PROVIDER_URL}/baileys/send`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          to: phone,
          content: renderedMessage
        })
      });

      const baileysResult = await baileysResponse.json();

      if (!baileysResult.success) {
        console.error(`[${transactionId}] Baileys send failed:`, baileysResult.error);
        return { status: 'ERROR', transactionId, details: baileysResult.error };
      }

      console.log(`[${transactionId}] Step 11: Message sent via Baileys, messageId: ${baileysResult.messageId}`);
      return { status: 'SENT', transactionId, details: { message: renderedMessage, messageId: baileysResult.messageId, provider: 'baileys' } };

    } else if (novu) {
      // Use Novu for production
      const subscriberId = recipient.userId || normalizePhone(recipient.phone!);

      await novu.trigger(eventType, {
        to: {
          subscriberId,
          phone: recipient.phone
        },
        payload: {
          message: renderedMessage,
          ...data
        },
        transactionId
      });
      console.log(`[${transactionId}] Step 11: Novu workflow triggered`);
      return { status: 'SENT', transactionId, details: { message: renderedMessage, provider: 'novu' } };

    } else {
      console.log(`[${transactionId}] Step 11: SIMULATED - No provider configured. Message: ${renderedMessage}`);
      return { status: 'SIMULATED', transactionId, details: { message: renderedMessage, provider: 'none' } };
    }

  } catch (error) {
    console.error(`[${transactionId}] Error:`, error);
    return { status: 'ERROR', transactionId, details: String(error) };
  }
}

// Helper: Fetch config from config service
async function fetchConfig(tenantId: string, namespace: string, configCode: string): Promise<any> {
  try {
    const response = await fetch(`${CONFIG_SERVICE_URL}/configs/v1/_search`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        criteria: { tenantId, namespace, configCode, status: 'ACTIVE' }
      })
    });
    const data = await response.json();
    return data.configs?.[0];
  } catch (error) {
    console.warn(`Failed to fetch config ${namespace}/${configCode}:`, error);
    return null;
  }
}

// Helper: Fetch user preferences
async function fetchUserPreferences(userId: string, tenantId: string): Promise<any> {
  try {
    const response = await fetch(`${USER_PREFS_URL}/user-preferences/v1/_search`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        criteria: { userId, tenantId, preferenceCode: 'USER_NOTIFICATION_PREFERENCES' }
      })
    });
    const data = await response.json();
    return data.preferences?.[0];
  } catch (error) {
    console.warn('Failed to fetch user preferences:', error);
    return null;
  }
}

// Helper: Normalize phone to E.164
function normalizePhone(phone: string): string {
  const digits = phone.replace(/\D/g, '');
  if (digits.startsWith('91') && digits.length === 12) return `+${digits}`;
  if (digits.length === 10) return `+91${digits}`;
  return `+${digits}`;
}

// Kafka message handler
async function handleKafkaMessage({ topic, partition, message }: EachMessagePayload) {
  try {
    const value = message.value?.toString();
    if (!value) return;

    const event = JSON.parse(value);
    console.log(`Received Kafka message on ${topic}:`, event);

    // Map Kafka topic to event type
    const eventType = topic.replace(/-/g, '_').toUpperCase();

    await processNotification({
      eventType,
      tenantId: event.tenantId || 'pg.citya',
      recipient: {
        userId: event.userId || event.citizen?.uuid,
        phone: event.mobileNumber || event.citizen?.mobileNumber
      },
      data: event
    });
  } catch (error) {
    console.error('Kafka message processing error:', error);
  }
}

// Start Kafka consumer
async function startKafkaConsumer() {
  try {
    consumer = kafka.consumer({ groupId: KAFKA_GROUP_ID });
    await consumer.connect();

    for (const topic of KAFKA_TOPICS) {
      await consumer.subscribe({ topic, fromBeginning: false });
      console.log(`Subscribed to Kafka topic: ${topic}`);
    }

    await consumer.run({
      eachMessage: handleKafkaMessage
    });

    console.log('Kafka consumer started');
  } catch (error) {
    console.error('Failed to start Kafka consumer:', error);
    // Retry after delay
    setTimeout(startKafkaConsumer, 5000);
  }
}

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('Shutting down...');
  if (consumer) {
    await consumer.disconnect();
  }
  process.exit(0);
});

app.listen(PORT, async () => {
  console.log(`digit-novu-bridge listening on port ${PORT}`);
  // Start Kafka consumer in background
  startKafkaConsumer();
});
