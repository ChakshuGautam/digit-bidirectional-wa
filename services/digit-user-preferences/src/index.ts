import express from 'express';
import { Pool } from 'pg';
import { v4 as uuidv4 } from 'uuid';

const app = express();
app.use(express.json());

const PORT = process.env.SERVER_PORT || 8200;

// Database connection
const pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgresql://egov:egov123@postgres:5432/egov'
});

// Health check
app.get('/user-preferences/health', (req, res) => {
  res.json({ status: 'UP', service: 'digit-user-preferences' });
});

app.get('/user-preferences/actuator/health', (req, res) => {
  res.json({ status: 'UP' });
});

// POST /v1/_upsert - Create or update a preference
app.post('/user-preferences/v1/_upsert', async (req, res) => {
  try {
    const { requestInfo, preference } = req.body;

    if (!preference?.userId || !preference?.preferenceCode || !preference?.payload) {
      return res.status(400).json({
        responseInfo: { status: 'failed' },
        errors: [{ code: 'INVALID_REQUEST', message: 'userId, preferenceCode, and payload are required' }]
      });
    }

    const { userId, tenantId, preferenceCode, payload } = preference;
    const id = preference.id || uuidv4();
    const now = Date.now();
    const createdBy = requestInfo?.userInfo?.uuid || 'SYSTEM';

    // Upsert query
    const query = `
      INSERT INTO user_preferences (id, user_id, tenant_id, preference_code, payload, created_by, created_time, last_modified_by, last_modified_time)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $6, $7)
      ON CONFLICT (user_id, preference_code)
      DO UPDATE SET
        payload = $5,
        last_modified_by = $6,
        last_modified_time = $7
      RETURNING *
    `;

    const result = await pool.query(query, [id, userId, tenantId, preferenceCode, JSON.stringify(payload), createdBy, now]);
    const row = result.rows[0];

    res.json({
      responseInfo: { status: 'successful' },
      preferences: [{
        id: row.id,
        userId: row.user_id,
        tenantId: row.tenant_id,
        preferenceCode: row.preference_code,
        payload: row.payload,
        auditDetails: {
          createdBy: row.created_by,
          createdTime: parseInt(row.created_time),
          lastModifiedBy: row.last_modified_by,
          lastModifiedTime: parseInt(row.last_modified_time)
        }
      }]
    });
  } catch (error) {
    console.error('Upsert error:', error);
    res.status(500).json({
      responseInfo: { status: 'failed' },
      errors: [{ code: 'INTERNAL_ERROR', message: String(error) }]
    });
  }
});

// POST /v1/_search - Search preferences
app.post('/user-preferences/v1/_search', async (req, res) => {
  try {
    const { criteria } = req.body;
    const { userId, tenantId, preferenceCode, limit = 100, offset = 0 } = criteria || {};

    let query = 'SELECT * FROM user_preferences WHERE 1=1';
    const params: any[] = [];
    let paramIndex = 1;

    if (userId) {
      query += ` AND user_id = $${paramIndex++}`;
      params.push(userId);
    }
    if (tenantId) {
      query += ` AND tenant_id = $${paramIndex++}`;
      params.push(tenantId);
    }
    if (preferenceCode) {
      query += ` AND preference_code = $${paramIndex++}`;
      params.push(preferenceCode);
    }

    query += ` ORDER BY last_modified_time DESC LIMIT $${paramIndex++} OFFSET $${paramIndex++}`;
    params.push(limit, offset);

    const result = await pool.query(query, params);

    res.json({
      responseInfo: { status: 'successful' },
      preferences: result.rows.map(row => ({
        id: row.id,
        userId: row.user_id,
        tenantId: row.tenant_id,
        preferenceCode: row.preference_code,
        payload: row.payload,
        auditDetails: {
          createdBy: row.created_by,
          createdTime: parseInt(row.created_time),
          lastModifiedBy: row.last_modified_by,
          lastModifiedTime: parseInt(row.last_modified_time)
        }
      })),
      pagination: { limit, offset, totalCount: result.rowCount }
    });
  } catch (error) {
    console.error('Search error:', error);
    res.status(500).json({
      responseInfo: { status: 'failed' },
      errors: [{ code: 'INTERNAL_ERROR', message: String(error) }]
    });
  }
});

// Initialize database schema
async function initDb() {
  const createTable = `
    CREATE TABLE IF NOT EXISTS user_preferences (
      id VARCHAR(64) PRIMARY KEY,
      user_id VARCHAR(64) NOT NULL,
      tenant_id VARCHAR(64),
      preference_code VARCHAR(128) NOT NULL,
      payload JSONB NOT NULL,
      created_by VARCHAR(64),
      created_time BIGINT,
      last_modified_by VARCHAR(64),
      last_modified_time BIGINT,
      UNIQUE(user_id, preference_code)
    );
    CREATE INDEX IF NOT EXISTS idx_user_preferences_user_id ON user_preferences(user_id);
    CREATE INDEX IF NOT EXISTS idx_user_preferences_tenant_id ON user_preferences(tenant_id);
  `;

  try {
    await pool.query(createTable);
    console.log('Database schema initialized');
  } catch (error) {
    console.error('Failed to initialize database:', error);
  }
}

app.listen(PORT, async () => {
  console.log(`digit-user-preferences listening on port ${PORT}`);
  await initDb();
});
