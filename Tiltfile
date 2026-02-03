# DIGIT Core Services - Tiltfile
# Run with: tilt up

# Load extensions
load('ext://uibutton', 'cmd_button', 'location')

# Load docker-compose configuration
docker_compose('./docker-compose.yml')

# ==================== Infrastructure ====================
dc_resource('postgres', labels=['infrastructure'])
dc_resource('redis', labels=['infrastructure'])
dc_resource('kafka', labels=['infrastructure'])
dc_resource('elasticsearch', labels=['infrastructure'])

# ==================== Core Services ====================
dc_resource('egov-mdms-service', labels=['core-services'],
    links=[
        link('http://localhost:18094/mdms-v2/health', 'Health'),
    ])

dc_resource('egov-enc-service', labels=['core-services'],
    links=[
        link('http://localhost:11234/egov-enc-service/actuator/health', 'Health'),
    ])

dc_resource('egov-idgen', labels=['core-services'],
    links=[
        link('http://localhost:18088/egov-idgen/health', 'Health'),
    ])

dc_resource('egov-user', labels=['core-services'],
    links=[
        link('http://localhost:18107/user/health', 'Health'),
    ])

dc_resource('egov-workflow-v2', labels=['core-services'],
    links=[
        link('http://localhost:18109/egov-workflow-v2/health', 'Health'),
    ])

dc_resource('egov-localization', labels=['core-services'],
    links=[
        link('http://localhost:18096/localization/actuator/health', 'Health'),
    ])

dc_resource('egov-location', labels=['core-services'],
    links=[
        link('http://localhost:18084/egov-location/health', 'Health'),
    ])

dc_resource('boundary-service', labels=['core-services'],
    links=[
        link('http://localhost:18081/boundary-service/actuator/health', 'Health'),
    ])

dc_resource('egov-accesscontrol', labels=['core-services'],
    links=[
        link('http://localhost:18090/access/health', 'Health'),
    ])

dc_resource('egov-persister', labels=['core-services'],
    links=[
        link('http://localhost:18091/common-persist/actuator/health', 'Health'),
    ])

# ==================== API Gateway ====================
dc_resource('kong', labels=['gateway'],
    links=[
        link('http://localhost:18000', 'Proxy'),
        link('http://localhost:18001', 'Admin API'),
        link('http://localhost:18002', 'Manager GUI'),
    ])

# Auto-reload Kong when kong.yml changes
local_resource(
    'kong-reload',
    cmd='docker exec kong-gateway kong reload',
    deps=['./kong/kong.yml'],
    labels=['gateway'],
    auto_init=False,
    trigger_mode=TRIGGER_MODE_AUTO,
)

# ==================== Seed Jobs ====================
dc_resource('db-seed', labels=['seeds'], auto_init=True)
dc_resource('idgen-seed', labels=['seeds'], auto_init=True)
dc_resource('mdms-tenant-seed', labels=['seeds'], auto_init=True)
dc_resource('mdms-workflow-seed', labels=['seeds'], auto_init=True)
dc_resource('localization-seed', labels=['seeds'], auto_init=True)

# ==================== Novu Notification Infrastructure ====================
dc_resource('novu-mongodb', labels=['novu-infrastructure'])

dc_resource('novu-api', labels=['novu-infrastructure'],
    links=[
        link('http://localhost:13000/v1/health-check', 'Health'),
        link('http://localhost:13000', 'API'),
    ])

dc_resource('novu-worker', labels=['novu-infrastructure'])

dc_resource('novu-web', labels=['novu-infrastructure'],
    links=[
        link('http://localhost:14200', 'Dashboard'),
    ])

dc_resource('novu-ws', labels=['novu-infrastructure'])

# ==================== WhatsApp Notification Services ====================
# These services have hot-reload enabled via volume mounts

dc_resource('digit-user-preferences', labels=['whatsapp-services'],
    links=[
        link('http://localhost:18200/user-preferences/health', 'Health'),
    ])

dc_resource('digit-config-service', labels=['whatsapp-services'],
    links=[
        link('http://localhost:18201/configs/health', 'Health'),
    ])

dc_resource('digit-novu-bridge', labels=['whatsapp-services'],
    links=[
        link('http://localhost:18202/novu-bridge/health', 'Health'),
    ])

dc_resource('baileys-provider', labels=['whatsapp-services'],
    links=[
        link('http://localhost:18203/baileys/health', 'Health'),
        link('http://localhost:18203/baileys/qr/page', 'QR Code (Scan)'),
        link('http://localhost:18203/baileys/status', 'Status'),
    ])

# ==================== Custom Buttons ====================

# Health Check button in the nav bar
cmd_button(
    name='health-check',
    argv=['bash', '/root/code/digit-2.9lts-core-storm/scripts/health-check.sh'],
    location=location.NAV,
    icon_name='favorite',
    text='Health Check',
)

# Smoke Tests button in the nav bar
cmd_button(
    name='smoke-tests',
    argv=['bash', '/root/code/digit-2.9lts-core-storm/scripts/smoke-tests.sh'],
    location=location.NAV,
    icon_name='science',
    text='Smoke Tests',
)

# Re-seed MDMS button (useful after restart)
cmd_button(
    name='reseed-mdms',
    argv=['sh', '-c', 'docker exec -i docker-postgres psql -U egov -d egov < ./db/seed.sql'],
    location=location.NAV,
    icon_name='refresh',
    text='Re-seed MDMS',
)

# Kong API Gateway test button
cmd_button(
    name='kong-test',
    argv=['bash', '/root/code/digit-2.9lts-core-storm/scripts/kong-test.sh', 'test'],
    location=location.NAV,
    icon_name='security',
    text='Kong Test',
)

# ==================== Port Summary ====================
# Infrastructure:
#   - Postgres:      15432
#   - Redis:         16379
#   - Kafka:         19092
#   - Elasticsearch: 19200
#
# API Gateway (Kong):
#   - Proxy:         18000 (external access point)
#   - Admin API:     18001
#   - Manager GUI:   18002
#   - Status:        18100
#
# Core Services (internal, use Kong for external access):
#   - MDMS:          18094
#   - ENC:           11234
#   - IDGEN:         18088
#   - User:          18107
#   - Workflow:      18109
#   - Localization:  18096
#   - Location:      18084
#   - Boundary-v2:   18081
#   - AccessControl: 18090
#   - Persister:     18091
#
# Novu Notification Infrastructure:
#   - MongoDB:       27017
#   - Novu API:      13000
#   - Novu Web:      14200 (Dashboard)
#   - Novu WS:       13002
#
# WhatsApp Notification Services (hot-reload enabled):
#   - User Prefs:    18200
#   - Config Svc:    18201
#   - Novu Bridge:   18202
#   - Baileys:       18203 (QR: /baileys/qr/page)
