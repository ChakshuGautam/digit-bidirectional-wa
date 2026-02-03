-- Create id_generator table for egov-idgen service
-- This must run before egov-idgen starts to avoid Flyway migration errors

-- Create the main table
CREATE TABLE IF NOT EXISTS id_generator (
    id BIGSERIAL PRIMARY KEY,
    idname VARCHAR(256) NOT NULL,
    tenantid VARCHAR(256) NOT NULL,
    format VARCHAR(256),
    sequencenumber BIGINT DEFAULT 1,
    CONSTRAINT uk_id_generator UNIQUE (idname, tenantid)
);

-- Create sequences that may be referenced by id formats
CREATE SEQUENCE IF NOT EXISTS seq_swm_trn_num START 1;
CREATE SEQUENCE IF NOT EXISTS seq_eg_pt_ptid START 1;
CREATE SEQUENCE IF NOT EXISTS seq_eg_tl_apl START 1;
CREATE SEQUENCE IF NOT EXISTS seq_eg_pg_rcpt START 1;
CREATE SEQUENCE IF NOT EXISTS seq_eg_bs_apl START 1;

-- Get the next installed_rank for flyway_schema_history
-- Mark all idgen migrations as completed so Flyway skips them

-- Main migrations
INSERT INTO flyway_schema_history (installed_rank, version, description, type, script, checksum, installed_by, installed_on, execution_time, success)
SELECT COALESCE((SELECT MAX(installed_rank) FROM flyway_schema_history), 0) + 1,
       '20170829163101', 'id gen create ddl', 'SQL', 'V20170829163101__id_gen_create_ddl.sql', 0, 'egov-seed', NOW(), 0, TRUE
WHERE NOT EXISTS (SELECT 1 FROM flyway_schema_history WHERE version = '20170829163101');

INSERT INTO flyway_schema_history (installed_rank, version, description, type, script, checksum, installed_by, installed_on, execution_time, success)
SELECT COALESCE((SELECT MAX(installed_rank) FROM flyway_schema_history), 0) + 1,
       '20171020231917', 'create swm transaction num seq ddl', 'SQL', 'V20171020231917__create_swm_transaction_num_seq_ddl.sql', 0, 'egov-seed', NOW(), 0, TRUE
WHERE NOT EXISTS (SELECT 1 FROM flyway_schema_history WHERE version = '20171020231917');

-- Dev migrations
INSERT INTO flyway_schema_history (installed_rank, version, description, type, script, checksum, installed_by, installed_on, execution_time, success)
SELECT COALESCE((SELECT MAX(installed_rank) FROM flyway_schema_history), 0) + 1,
       '20171020231801', 'id gen insert swm transaction num format', 'SQL', 'V20171020231801__id_gen_insert_swm_transaction_num_format.sql', 0, 'egov-seed', NOW(), 0, TRUE
WHERE NOT EXISTS (SELECT 1 FROM flyway_schema_history WHERE version = '20171020231801');

COMMIT;
