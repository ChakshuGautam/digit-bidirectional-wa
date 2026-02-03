import express from 'express';
import { Pool } from 'pg';
import { v4 as uuidv4 } from 'uuid';
import Handlebars from 'handlebars';

const app = express();
app.use(express.json());

const PORT = process.env.SERVER_PORT || 8201;

// Database connection
const pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgresql://egov:egov123@postgres:5432/egov'
});

// Health check
app.get('/configs/health', (req, res) => {
  res.json({ status: 'UP', service: 'digit-config-service' });
});

app.get('/configs/actuator/health', (req, res) => {
  res.json({ status: 'UP' });
});

// POST /v1/_create - Create a config
app.post('/configs/v1/_create', async (req, res) => {
  try {
    const { requestInfo, config } = req.body;

    if (!config?.tenantId || !config?.namespace || !config?.configName || !config?.configCode) {
      return res.status(400).json({
        responseInfo: { status: 'failed' },
        errors: [{ code: 'INVALID_REQUEST', message: 'tenantId, namespace, configName, and configCode are required' }]
      });
    }

    const id = uuidv4();
    const now = Date.now();
    const createdBy = requestInfo?.userInfo?.uuid || 'SYSTEM';
    const { tenantId, namespace, configName, configCode, version, status, environment, description, content } = config;

    const query = `
      INSERT INTO configs (id, tenant_id, namespace, config_name, config_code, version, status, environment, description, content, created_by, created_time, last_modified_by, last_modified_time)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $11, $12)
      RETURNING *
    `;

    const result = await pool.query(query, [
      id, tenantId, namespace, configName, configCode,
      version || '1.0.0', status || 'DRAFT', environment || 'dev',
      description, content ? JSON.stringify(content) : null,
      createdBy, now
    ]);

    const row = result.rows[0];
    res.status(201).json({
      responseInfo: { status: 'successful' },
      configs: [mapRowToConfig(row)]
    });
  } catch (error) {
    console.error('Create error:', error);
    res.status(500).json({
      responseInfo: { status: 'failed' },
      errors: [{ code: 'INTERNAL_ERROR', message: String(error) }]
    });
  }
});

// POST /v1/_update - Update a config
app.post('/configs/v1/_update', async (req, res) => {
  try {
    const { requestInfo, config } = req.body;

    if (!config?.id && !config?.configCode) {
      return res.status(400).json({
        responseInfo: { status: 'failed' },
        errors: [{ code: 'INVALID_REQUEST', message: 'id or configCode required' }]
      });
    }

    const now = Date.now();
    const modifiedBy = requestInfo?.userInfo?.uuid || 'SYSTEM';

    const query = `
      UPDATE configs SET
        config_name = COALESCE($1, config_name),
        version = COALESCE($2, version),
        status = COALESCE($3, status),
        environment = COALESCE($4, environment),
        description = COALESCE($5, description),
        content = COALESCE($6, content),
        last_modified_by = $7,
        last_modified_time = $8
      WHERE id = $9 OR config_code = $10
      RETURNING *
    `;

    const result = await pool.query(query, [
      config.configName, config.version, config.status, config.environment,
      config.description, config.content ? JSON.stringify(config.content) : null,
      modifiedBy, now, config.id, config.configCode
    ]);

    if (result.rowCount === 0) {
      return res.status(404).json({
        responseInfo: { status: 'failed' },
        errors: [{ code: 'NOT_FOUND', message: 'Config not found' }]
      });
    }

    res.json({
      responseInfo: { status: 'successful' },
      configs: [mapRowToConfig(result.rows[0])]
    });
  } catch (error) {
    console.error('Update error:', error);
    res.status(500).json({
      responseInfo: { status: 'failed' },
      errors: [{ code: 'INTERNAL_ERROR', message: String(error) }]
    });
  }
});

// POST /v1/_search - Search configs
app.post('/configs/v1/_search', async (req, res) => {
  try {
    const { criteria } = req.body;
    const { tenantId, namespace, configName, configCode, environment, status, version, includeContent = true, limit = 100, offset = 0 } = criteria || {};

    let query = `SELECT ${includeContent ? '*' : 'id, tenant_id, namespace, config_name, config_code, version, status, environment, description, created_by, created_time, last_modified_by, last_modified_time'} FROM configs WHERE 1=1`;
    const params: any[] = [];
    let paramIndex = 1;

    if (tenantId) { query += ` AND tenant_id = $${paramIndex++}`; params.push(tenantId); }
    if (namespace) { query += ` AND namespace = $${paramIndex++}`; params.push(namespace); }
    if (configName) { query += ` AND config_name = $${paramIndex++}`; params.push(configName); }
    if (configCode) { query += ` AND config_code = $${paramIndex++}`; params.push(configCode); }
    if (environment) { query += ` AND environment = $${paramIndex++}`; params.push(environment); }
    if (status) { query += ` AND status = $${paramIndex++}`; params.push(status); }
    if (version) { query += ` AND version = $${paramIndex++}`; params.push(version); }

    query += ` ORDER BY last_modified_time DESC LIMIT $${paramIndex++} OFFSET $${paramIndex++}`;
    params.push(limit, offset);

    const result = await pool.query(query, params);

    res.json({
      responseInfo: { status: 'successful' },
      configs: result.rows.map(mapRowToConfig),
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

// POST /v1/_activate - Activate a config set
app.post('/configs/v1/_activate', async (req, res) => {
  try {
    const { tenantId, configSetId } = req.body;

    // Activate all configs with this configSetId
    const query = `
      UPDATE configs SET status = 'ACTIVE', last_modified_time = $1
      WHERE tenant_id = $2 AND (config_code LIKE $3 || '%' OR id = $3)
      RETURNING config_code
    `;

    const result = await pool.query(query, [Date.now(), tenantId, configSetId]);

    res.json({
      responseInfo: { status: 'successful' },
      configSetId,
      status: 'ACTIVE',
      activatedCount: result.rowCount
    });
  } catch (error) {
    console.error('Activate error:', error);
    res.status(500).json({
      responseInfo: { status: 'failed' },
      errors: [{ code: 'INTERNAL_ERROR', message: String(error) }]
    });
  }
});

// POST /v1/template/_preview - Render a template preview
app.post('/configs/v1/template/_preview', async (req, res) => {
  try {
    const { tenantId, template, locale, data } = req.body;

    // Fetch template from DB
    const query = `
      SELECT content FROM configs
      WHERE tenant_id = $1 AND namespace = $2 AND config_code = $3 AND status = 'ACTIVE'
      LIMIT 1
    `;

    const result = await pool.query(query, [tenantId, template?.namespace, template?.configCode]);

    if (result.rowCount === 0) {
      return res.status(404).json({
        responseInfo: { status: 'failed' },
        errors: [{ code: 'TEMPLATE_NOT_FOUND', message: 'Template not found' }]
      });
    }

    const templateContent = result.rows[0].content;
    const localeKey = locale || 'en_IN';
    const templateText = templateContent?.templates?.[localeKey] || templateContent?.templates?.['en_IN'] || '';

    // Render with Handlebars
    const compiled = Handlebars.compile(templateText);
    const rendered = compiled(data || {});

    res.json({
      responseInfo: { status: 'successful' },
      rendered,
      locale: localeKey
    });
  } catch (error) {
    console.error('Template preview error:', error);
    res.status(500).json({
      responseInfo: { status: 'failed' },
      errors: [{ code: 'INTERNAL_ERROR', message: String(error) }]
    });
  }
});

function mapRowToConfig(row: any) {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    namespace: row.namespace,
    configName: row.config_name,
    configCode: row.config_code,
    version: row.version,
    status: row.status,
    environment: row.environment,
    description: row.description,
    content: row.content,
    auditDetails: {
      createdBy: row.created_by,
      createdTime: parseInt(row.created_time),
      lastModifiedBy: row.last_modified_by,
      lastModifiedTime: parseInt(row.last_modified_time)
    }
  };
}

// Initialize database schema
async function initDb() {
  const createTable = `
    CREATE TABLE IF NOT EXISTS configs (
      id VARCHAR(64) PRIMARY KEY,
      tenant_id VARCHAR(64) NOT NULL,
      namespace VARCHAR(128) NOT NULL,
      config_name VARCHAR(128) NOT NULL,
      config_code VARCHAR(128) NOT NULL,
      version VARCHAR(64) DEFAULT '1.0.0',
      status VARCHAR(32) DEFAULT 'DRAFT',
      environment VARCHAR(32) DEFAULT 'dev',
      description VARCHAR(1024),
      content JSONB,
      created_by VARCHAR(64),
      created_time BIGINT,
      last_modified_by VARCHAR(64),
      last_modified_time BIGINT,
      UNIQUE(tenant_id, namespace, config_code, version)
    );
    CREATE INDEX IF NOT EXISTS idx_configs_tenant_namespace ON configs(tenant_id, namespace);
    CREATE INDEX IF NOT EXISTS idx_configs_code ON configs(config_code);
    CREATE INDEX IF NOT EXISTS idx_configs_status ON configs(status);
  `;

  try {
    await pool.query(createTable);
    console.log('Database schema initialized');
  } catch (error) {
    console.error('Failed to initialize database:', error);
  }
}

app.listen(PORT, async () => {
  console.log(`digit-config-service listening on port ${PORT}`);
  await initDb();
});
