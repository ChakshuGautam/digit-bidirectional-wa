import express from 'express';
import makeWASocket, {
  DisconnectReason,
  useMultiFileAuthState,
  WASocket
} from 'baileys';
import { Boom } from '@hapi/boom';
import QRCode from 'qrcode';

const app = express();
app.use(express.json());

const PORT = parseInt(process.env.SERVER_PORT || '8203', 10);
const AUTH_DIR = process.env.AUTH_DIR || './auth_info';
const MOCK_MODE = process.env.MOCK_MODE === 'true';

// WhatsApp connection state
let sock: WASocket | null = null;
let qrCode: string | null = null;
let connectionStatus: 'disconnected' | 'connecting' | 'connected' | 'qr_pending' = 'disconnected';
let lastError: string | null = null;

// Health check
app.get('/baileys/health', (req, res) => {
  res.json({
    status: 'UP',
    service: 'baileys-provider',
    mode: MOCK_MODE ? 'mock' : 'live',
    whatsapp: {
      status: MOCK_MODE ? 'mock_connected' : connectionStatus,
      hasQR: MOCK_MODE ? false : !!qrCode,
      lastError: MOCK_MODE ? null : lastError
    }
  });
});

app.get('/baileys/actuator/health', (req, res) => {
  res.json({ status: 'UP' });
});

// Get QR code for authentication (as JSON)
app.get('/baileys/qr', async (req, res) => {
  if (connectionStatus === 'connected') {
    return res.json({
      status: 'already_connected',
      message: 'WhatsApp is already connected'
    });
  }

  if (!qrCode) {
    return res.status(404).json({
      status: 'no_qr',
      message: 'No QR code available. Connection may be initializing or already authenticated.'
    });
  }

  try {
    const qrDataUrl = await QRCode.toDataURL(qrCode);
    res.json({
      status: 'qr_ready',
      qr: qrDataUrl,
      qrRaw: qrCode,
      message: 'Scan this QR code with WhatsApp'
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to generate QR image' });
  }
});

// Get QR as HTML page (easy to scan)
app.get('/baileys/qr/page', async (req, res) => {
  if (connectionStatus === 'connected') {
    return res.send(`
      <html>
        <body style="display:flex;justify-content:center;align-items:center;height:100vh;font-family:sans-serif;">
          <div style="text-align:center;">
            <h1 style="color:green;">Connected to WhatsApp</h1>
            <p>You can close this page.</p>
          </div>
        </body>
      </html>
    `);
  }

  if (!qrCode) {
    return res.send(`
      <html>
        <head><meta http-equiv="refresh" content="3"></head>
        <body style="display:flex;justify-content:center;align-items:center;height:100vh;font-family:sans-serif;">
          <div style="text-align:center;">
            <h1>Waiting for QR Code...</h1>
            <p>Page will refresh automatically.</p>
            <p>Status: ${connectionStatus}</p>
          </div>
        </body>
      </html>
    `);
  }

  try {
    const qrDataUrl = await QRCode.toDataURL(qrCode, { width: 300 });
    res.send(`
      <html>
        <head><meta http-equiv="refresh" content="30"></head>
        <body style="display:flex;justify-content:center;align-items:center;height:100vh;font-family:sans-serif;">
          <div style="text-align:center;">
            <h1>Scan QR Code with WhatsApp</h1>
            <img src="${qrDataUrl}" alt="WhatsApp QR Code" />
            <p>Open WhatsApp > Settings > Linked Devices > Link a Device</p>
            <p style="color:gray;">Page refreshes every 30 seconds</p>
          </div>
        </body>
      </html>
    `);
  } catch (error) {
    res.status(500).send('Failed to generate QR');
  }
});

// Send message endpoint
app.post('/baileys/send', async (req, res) => {
  try {
    const { to, content, payload } = req.body;

    // Support both direct format and Novu webhook format
    const phoneNumber = to || payload?.to || req.body.subscriber?.phone;
    const message = content || payload?.message || payload?.content || req.body.content;

    if (!phoneNumber || !message) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: to (phone number) and content (message)'
      });
    }

    // Format phone number to WhatsApp JID
    const jid = formatPhoneToJid(phoneNumber);

    // MOCK MODE: Log the message instead of sending
    if (MOCK_MODE) {
      const mockId = `mock_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      console.log('\n' + '='.repeat(60));
      console.log('MOCK WhatsApp Message');
      console.log('='.repeat(60));
      console.log(`To: ${jid}`);
      console.log(`Message: ${message}`);
      console.log(`Mock ID: ${mockId}`);
      console.log('='.repeat(60) + '\n');

      return res.json({
        success: true,
        messageId: mockId,
        to: jid,
        timestamp: Date.now(),
        mode: 'mock'
      });
    }

    // LIVE MODE: Require connection
    if (!sock || connectionStatus !== 'connected') {
      return res.status(503).json({
        success: false,
        error: 'WhatsApp not connected. Please scan QR code first.',
        qrUrl: `http://localhost:${PORT}/baileys/qr/page`
      });
    }

    console.log(`Sending message to ${jid}: ${message.substring(0, 50)}...`);

    // Send message
    const result = await sock.sendMessage(jid, { text: message });

    res.json({
      success: true,
      messageId: result?.key?.id,
      to: jid,
      timestamp: Date.now(),
      mode: 'live'
    });
  } catch (error) {
    console.error('Send error:', error);
    res.status(500).json({
      success: false,
      error: String(error)
    });
  }
});

// Novu Chat Webhook endpoint - receives messages from Novu workflows
app.post('/baileys/novu-webhook', async (req, res) => {
  try {
    const { content, phoneNumber, webhookUrl, channel, ...extra } = req.body;

    // Log the incoming webhook for debugging
    console.log('Novu webhook received:', { phoneNumber, channel, contentLength: content?.length });

    if (!phoneNumber || !content) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: phoneNumber and content'
      });
    }

    // MOCK MODE: Log the message instead of sending
    if (MOCK_MODE) {
      const mockId = `novu_mock_${Date.now()}`;
      console.log('\n' + '='.repeat(60));
      console.log('MOCK Novu Webhook Message');
      console.log('='.repeat(60));
      console.log(`To: ${phoneNumber}`);
      console.log(`Content: ${content}`);
      console.log('='.repeat(60) + '\n');

      return res.json({
        success: true,
        id: mockId,
        date: new Date().toISOString()
      });
    }

    // LIVE MODE: Require connection
    if (!sock || connectionStatus !== 'connected') {
      return res.status(503).json({
        success: false,
        error: 'WhatsApp not connected'
      });
    }

    // Format phone number to WhatsApp JID
    const jid = formatPhoneToJid(phoneNumber);
    console.log(`Sending Novu message to ${jid}`);

    // Send message
    const result = await sock.sendMessage(jid, { text: content });

    res.json({
      success: true,
      id: result?.key?.id || `baileys_${Date.now()}`,
      date: new Date().toISOString()
    });
  } catch (error) {
    console.error('Novu webhook error:', error);
    res.status(500).json({
      success: false,
      error: String(error)
    });
  }
});

// Disconnect endpoint
app.post('/baileys/disconnect', async (req, res) => {
  if (sock) {
    await sock.logout();
    sock = null;
  }
  connectionStatus = 'disconnected';
  qrCode = null;
  res.json({ success: true, message: 'Disconnected from WhatsApp' });
});

// Reconnect endpoint
app.post('/baileys/reconnect', async (req, res) => {
  if (sock) {
    sock.end(undefined);
    sock = null;
  }
  connectionStatus = 'disconnected';
  qrCode = null;

  // Restart connection
  startWhatsApp();
  res.json({ success: true, message: 'Reconnecting...' });
});

// Status endpoint
app.get('/baileys/status', (req, res) => {
  res.json({
    connected: connectionStatus === 'connected',
    status: connectionStatus,
    hasQR: !!qrCode,
    lastError
  });
});

// Format phone number to WhatsApp JID
function formatPhoneToJid(phone: string): string {
  // Remove all non-numeric characters
  let cleaned = phone.replace(/\D/g, '');

  // If starts with 0, assume Indian number, replace with 91
  if (cleaned.startsWith('0')) {
    cleaned = '91' + cleaned.substring(1);
  }

  // If 10 digits, assume Indian number
  if (cleaned.length === 10) {
    cleaned = '91' + cleaned;
  }

  return cleaned + '@s.whatsapp.net';
}

// Initialize WhatsApp connection - SIMPLIFIED following official docs
async function startWhatsApp() {
  try {
    connectionStatus = 'connecting';
    console.log('Starting WhatsApp connection...');

    const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR);

    // Minimal config - following official Baileys documentation pattern
    sock = makeWASocket({
      auth: state,
      browser: ['DIGIT', 'Chrome', '122.0']
    });

    // Handle connection updates
    sock.ev.on('connection.update', (update) => {
      const { connection, lastDisconnect, qr } = update;

      // QR code received
      if (qr) {
        qrCode = qr;
        connectionStatus = 'qr_pending';
        console.log('\n========================================');
        console.log('QR Code received! Scan with WhatsApp.');
        console.log(`Or visit: http://localhost:${PORT}/baileys/qr/page`);
        console.log('========================================\n');
      }

      // Connection closed
      if (connection === 'close') {
        qrCode = null;
        const error = lastDisconnect?.error as Boom;
        const statusCode = error?.output?.statusCode;
        const shouldReconnect = statusCode !== DisconnectReason.loggedOut;

        lastError = error?.message || 'Connection closed';
        connectionStatus = 'disconnected';
        console.log('Connection closed:', lastError);
        console.log('Status code:', statusCode);

        if (shouldReconnect) {
          // Add delay before reconnecting to avoid spamming WhatsApp servers
          const delay = 5000 + Math.random() * 5000; // 5-10 seconds
          console.log(`Reconnecting in ${Math.round(delay/1000)}s...`);
          setTimeout(startWhatsApp, delay);
        } else {
          console.log('Logged out. Delete auth_info folder and restart to re-authenticate.');
        }
      }

      // Connection opened
      if (connection === 'open') {
        qrCode = null;
        lastError = null;
        connectionStatus = 'connected';
        console.log('\n========================================');
        console.log('WhatsApp connected successfully!');
        console.log('========================================\n');
      }
    });

    // Save credentials on update
    sock.ev.on('creds.update', saveCreds);

    // Log incoming messages (for debugging)
    sock.ev.on('messages.upsert', ({ messages }) => {
      for (const msg of messages) {
        if (!msg.key.fromMe && msg.message) {
          const from = msg.key.remoteJid;
          const text = msg.message.conversation ||
                       msg.message.extendedTextMessage?.text ||
                       '[media/other]';
          console.log(`Received from ${from}: ${text}`);
        }
      }
    });

  } catch (error) {
    console.error('Failed to start WhatsApp:', error);
    lastError = String(error);
    connectionStatus = 'disconnected';

    // Retry after delay
    console.log('Retrying in 5 seconds...');
    setTimeout(startWhatsApp, 5000);
  }
}

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('Shutting down...');
  if (sock) {
    sock.end(undefined);
  }
  process.exit(0);
});

app.listen(Number(PORT), '0.0.0.0', () => {
  console.log(`baileys-provider listening on 0.0.0.0:${PORT}`);
  if (MOCK_MODE) {
    console.log('Running in MOCK MODE - messages will be logged, not sent');
    connectionStatus = 'connected'; // Fake connected status in mock mode
  } else {
    console.log(`QR Page: http://localhost:${PORT}/baileys/qr/page`);
    startWhatsApp();
  }
});
