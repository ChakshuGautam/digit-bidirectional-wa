-- Seed minimal Workflow.BusinessServiceMasterConfig so workflow service can bootstrap
INSERT INTO eg_mdms_schema_definition (id, tenantid, code, description, definition, isactive, createdby, lastmodifiedby, createdtime, lastmodifiedtime)
SELECT 'workflow-bsm-schema', 'pg', 'Workflow.BusinessServiceMasterConfig', 'Workflow.BusinessServiceMasterConfig',
'{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "businessService": {"type": "string"},
    "isStatelevel": {"type": "string"},
    "active": {"type": "string"}
  },
  "required": ["businessService", "isStatelevel", "active"],
  "title": "Workflow business service state-level config"
}'::jsonb,
TRUE, 'system-mdms-seed', 'system-mdms-seed',
EXTRACT(EPOCH FROM NOW())::bigint * 1000,
EXTRACT(EPOCH FROM NOW())::bigint * 1000
WHERE NOT EXISTS (
  SELECT 1 FROM eg_mdms_schema_definition
  WHERE tenantid='pg' AND code='Workflow.BusinessServiceMasterConfig'
);

INSERT INTO eg_mdms_data (id, tenantid, uniqueidentifier, schemacode, data, isactive, createdby, lastmodifiedby, createdtime, lastmodifiedtime)
VALUES
  ('workflow-bsm-incident', 'pg', 'Workflow.BusinessServiceMasterConfig.Incident', 'Workflow.BusinessServiceMasterConfig',
   '{"businessService":"Incident","isStatelevel":"true","active":"true"}'::jsonb,
   TRUE, 'system-mdms-seed', 'system-mdms-seed',
   EXTRACT(EPOCH FROM NOW())::bigint * 1000,
   EXTRACT(EPOCH FROM NOW())::bigint * 1000),
  ('workflow-bsm-default', 'pg', 'Workflow.BusinessServiceMasterConfig.Default', 'Workflow.BusinessServiceMasterConfig',
   '{"businessService":"Default","isStatelevel":"false","active":"true"}'::jsonb,
   TRUE, 'system-mdms-seed', 'system-mdms-seed',
   EXTRACT(EPOCH FROM NOW())::bigint * 1000,
   EXTRACT(EPOCH FROM NOW())::bigint * 1000)
ON CONFLICT (tenantid, schemacode, uniqueidentifier) DO NOTHING;
