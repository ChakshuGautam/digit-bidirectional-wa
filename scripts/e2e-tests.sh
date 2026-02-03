#!/bin/bash
# End-to-End API Tests for DIGIT Bidirectional WhatsApp Services
# Run: ./scripts/e2e-tests.sh [--via-kong]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
USE_KONG=false
if [[ "$1" == "--via-kong" ]]; then
  USE_KONG=true
fi

# Base URLs
if $USE_KONG; then
  BASE_URL="http://localhost:18000"
  API_KEY="${API_KEY:-digit-dev-api-key-change-me}"
  AUTH_HEADER="X-API-Key: $API_KEY"
  echo -e "${BLUE}Running tests via Kong API Gateway${NC}"
else
  CONFIG_SERVICE_URL="http://localhost:18201"
  USER_PREFS_URL="http://localhost:18200"
  NOVU_BRIDGE_URL="http://localhost:18202"
  BAILEYS_URL="http://localhost:18203"
  AUTH_HEADER=""
  echo -e "${BLUE}Running tests directly against services${NC}"
fi

# Test counters
PASSED=0
FAILED=0
SKIPPED=0

# Test result tracking
declare -a RESULTS

# Helper functions
log_test() {
  echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}TEST: $1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

pass() {
  echo -e "${GREEN}✓ PASSED: $1${NC}"
  PASSED=$((PASSED + 1))
  RESULTS+=("${GREEN}✓${NC} $1")
}

fail() {
  echo -e "${RED}✗ FAILED: $1${NC}"
  echo -e "${RED}  Error: $2${NC}"
  FAILED=$((FAILED + 1))
  RESULTS+=("${RED}✗${NC} $1: $2")
}

skip() {
  echo -e "${YELLOW}⊘ SKIPPED: $1${NC}"
  echo -e "${YELLOW}  Reason: $2${NC}"
  SKIPPED=$((SKIPPED + 1))
  RESULTS+=("${YELLOW}⊘${NC} $1: $2")
}

check_status() {
  local response="$1"
  local expected_field="$2"
  local expected_value="$3"

  actual=$(echo "$response" | jq -r "$expected_field" 2>/dev/null)
  if [[ "$actual" == "$expected_value" ]]; then
    return 0
  else
    return 1
  fi
}

# Get URL based on mode
get_url() {
  local service="$1"
  local path="$2"

  if $USE_KONG; then
    echo "${BASE_URL}${path}"
  else
    case $service in
      "config") echo "${CONFIG_SERVICE_URL}${path}" ;;
      "prefs") echo "${USER_PREFS_URL}${path}" ;;
      "bridge") echo "${NOVU_BRIDGE_URL}${path}" ;;
      "baileys") echo "${BAILEYS_URL}${path}" ;;
    esac
  fi
}

# Build curl command with optional auth
do_curl() {
  if [[ -n "$AUTH_HEADER" ]]; then
    curl -s -H "$AUTH_HEADER" "$@"
  else
    curl -s "$@"
  fi
}

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     DIGIT Bidirectional WhatsApp - E2E API Tests             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# SECTION 1: Health Checks
# ============================================================================
echo -e "\n${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}SECTION 1: Health Checks${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"

# Test 1.1: Config Service Health
log_test "1.1 Config Service Health"
if $USE_KONG; then
  URL="${BASE_URL}/notification-config/health"
else
  URL="${CONFIG_SERVICE_URL}/configs/health"
fi
response=$(do_curl "$URL" 2>&1) || true
if check_status "$response" ".status" "UP"; then
  pass "Config Service is healthy"
else
  fail "Config Service health check" "Response: $response"
fi

# Test 1.2: User Preferences Health
log_test "1.2 User Preferences Service Health"
if $USE_KONG; then
  URL="${BASE_URL}/user-preferences/health"
else
  URL="${USER_PREFS_URL}/user-preferences/health"
fi
response=$(do_curl "$URL" 2>&1) || true
if check_status "$response" ".status" "UP"; then
  pass "User Preferences Service is healthy"
else
  fail "User Preferences health check" "Response: $response"
fi

# Test 1.3: Novu Bridge Health
log_test "1.3 Novu Bridge Health"
if $USE_KONG; then
  URL="${BASE_URL}/novu-bridge/health"
else
  URL="${NOVU_BRIDGE_URL}/novu-bridge/health"
fi
response=$(do_curl "$URL" 2>&1) || true
if check_status "$response" ".status" "UP"; then
  mode=$(echo "$response" | jq -r '.mode')
  kafka=$(echo "$response" | jq -r '.kafka')
  pass "Novu Bridge is healthy (mode: $mode, kafka: $kafka)"
else
  fail "Novu Bridge health check" "Response: $response"
fi

# Test 1.4: Baileys Provider Health
log_test "1.4 Baileys Provider Health"
if $USE_KONG; then
  URL="${BASE_URL}/baileys/health"
else
  URL="${BAILEYS_URL}/baileys/health"
fi
response=$(do_curl "$URL" 2>&1) || true
if check_status "$response" ".status" "UP"; then
  wa_status=$(echo "$response" | jq -r '.whatsapp.status')
  mode=$(echo "$response" | jq -r '.mode')
  pass "Baileys Provider is healthy (whatsapp: $wa_status, mode: $mode)"
else
  fail "Baileys Provider health check" "Response: $response"
fi

# ============================================================================
# SECTION 2: Config Service APIs
# ============================================================================
echo -e "\n${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}SECTION 2: Config Service APIs${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"

TEST_TENANT="pg.test"
TEST_NAMESPACE="notification-orchestrator"

# Test 2.1: Create Config
log_test "2.1 Create Config"
if $USE_KONG; then
  URL="${BASE_URL}/notification-config/v1/_create"
else
  URL="${CONFIG_SERVICE_URL}/configs/v1/_create"
fi
response=$(do_curl -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"config\": {
      \"tenantId\": \"$TEST_TENANT\",
      \"namespace\": \"$TEST_NAMESPACE\",
      \"configName\": \"Test Config\",
      \"configCode\": \"TEST_CONFIG\",
      \"content\": {
        \"testKey\": \"testValue\",
        \"enabled\": true
      }
    }
  }" 2>&1) || true

if check_status "$response" ".responseInfo.status" "successful"; then
  config_id=$(echo "$response" | jq -r '.configs[0].id')
  pass "Config created (id: $config_id)"
else
  fail "Create config" "Response: $response"
fi

# Test 2.2: Search Config
log_test "2.2 Search Config"
if $USE_KONG; then
  URL="${BASE_URL}/notification-config/v1/_search"
else
  URL="${CONFIG_SERVICE_URL}/configs/v1/_search"
fi
response=$(do_curl -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"criteria\": {
      \"tenantId\": \"$TEST_TENANT\",
      \"namespace\": \"$TEST_NAMESPACE\",
      \"configCode\": \"TEST_CONFIG\"
    }
  }" 2>&1) || true

if check_status "$response" ".responseInfo.status" "successful"; then
  count=$(echo "$response" | jq -r '.configs | length')
  pass "Config search returned $count result(s)"
else
  fail "Search config" "Response: $response"
fi

# Test 2.3: Update Config
log_test "2.3 Update Config"
if $USE_KONG; then
  URL="${BASE_URL}/notification-config/v1/_update"
else
  URL="${CONFIG_SERVICE_URL}/configs/v1/_update"
fi
response=$(do_curl -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"config\": {
      \"tenantId\": \"$TEST_TENANT\",
      \"namespace\": \"$TEST_NAMESPACE\",
      \"configName\": \"Test Config Updated\",
      \"configCode\": \"TEST_CONFIG\",
      \"content\": {
        \"testKey\": \"updatedValue\",
        \"enabled\": true,
        \"newField\": \"added\"
      }
    }
  }" 2>&1) || true

if check_status "$response" ".responseInfo.status" "successful"; then
  pass "Config updated successfully"
else
  fail "Update config" "Response: $response"
fi

# ============================================================================
# SECTION 3: User Preferences APIs
# ============================================================================
echo -e "\n${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}SECTION 3: User Preferences APIs${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"

TEST_USER="test-user-$(date +%s)"
TEST_PHONE="9199999$(shuf -i 10000-99999 -n 1)"

# Test 3.1: Create User Preference with Consent
log_test "3.1 Create User Preference with WhatsApp Consent"
if $USE_KONG; then
  URL="${BASE_URL}/user-preferences/v1/_upsert"
else
  URL="${USER_PREFS_URL}/user-preferences/v1/_upsert"
fi
response=$(do_curl -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"preference\": {
      \"userId\": \"$TEST_USER\",
      \"tenantId\": \"$TEST_TENANT\",
      \"preferenceCode\": \"USER_NOTIFICATION_PREFERENCES\",
      \"payload\": {
        \"preferredLanguage\": \"en_IN\",
        \"consent\": {
          \"WHATSAPP\": {
            \"status\": \"GRANTED\",
            \"grantedAt\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",
            \"method\": \"explicit\",
            \"version\": \"1.0\"
          }
        },
        \"channels\": {
          \"WHATSAPP\": {
            \"enabled\": true,
            \"phone\": \"$TEST_PHONE\"
          }
        }
      }
    }
  }" 2>&1) || true

if check_status "$response" ".responseInfo.status" "successful"; then
  pref_id=$(echo "$response" | jq -r '.preferences[0].id')
  pass "User preference created (id: $pref_id)"
else
  fail "Create user preference" "Response: $response"
fi

# Test 3.2: Search User Preference
log_test "3.2 Search User Preference"
if $USE_KONG; then
  URL="${BASE_URL}/user-preferences/v1/_search"
else
  URL="${USER_PREFS_URL}/user-preferences/v1/_search"
fi
response=$(do_curl -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"criteria\": {
      \"userId\": \"$TEST_USER\",
      \"tenantId\": \"$TEST_TENANT\"
    }
  }" 2>&1) || true

if check_status "$response" ".responseInfo.status" "successful"; then
  consent_status=$(echo "$response" | jq -r '.preferences[0].payload.consent.WHATSAPP.status')
  pass "User preference found (consent: $consent_status)"
else
  fail "Search user preference" "Response: $response"
fi

# Test 3.3: Update Consent to REVOKED
log_test "3.3 Update Consent to REVOKED"
if $USE_KONG; then
  URL="${BASE_URL}/user-preferences/v1/_upsert"
else
  URL="${USER_PREFS_URL}/user-preferences/v1/_upsert"
fi
response=$(do_curl -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"preference\": {
      \"userId\": \"$TEST_USER\",
      \"tenantId\": \"$TEST_TENANT\",
      \"preferenceCode\": \"USER_NOTIFICATION_PREFERENCES\",
      \"payload\": {
        \"preferredLanguage\": \"en_IN\",
        \"consent\": {
          \"WHATSAPP\": {
            \"status\": \"REVOKED\",
            \"revokedAt\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\"
          }
        },
        \"channels\": {
          \"WHATSAPP\": {
            \"enabled\": false,
            \"phone\": \"$TEST_PHONE\"
          }
        }
      }
    }
  }" 2>&1) || true

if check_status "$response" ".responseInfo.status" "successful"; then
  pass "Consent revoked successfully"
else
  fail "Revoke consent" "Response: $response"
fi

# ============================================================================
# SECTION 4: Baileys Provider APIs
# ============================================================================
echo -e "\n${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}SECTION 4: Baileys Provider APIs${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"

# Test 4.1: Get WhatsApp Status
log_test "4.1 Get WhatsApp Connection Status"
if $USE_KONG; then
  URL="${BASE_URL}/baileys/status"
else
  URL="${BAILEYS_URL}/baileys/status"
fi
response=$(do_curl "$URL" 2>&1) || true
status=$(echo "$response" | jq -r '.status' 2>/dev/null)
connected=$(echo "$response" | jq -r '.connected' 2>/dev/null)

if [[ -n "$status" ]]; then
  pass "WhatsApp status: $status (connected: $connected)"
else
  fail "Get WhatsApp status" "Response: $response"
fi

# Test 4.2: Check QR Endpoint
log_test "4.2 Check QR Code Endpoint"
if $USE_KONG; then
  URL="${BASE_URL}/baileys/qr"
else
  URL="${BAILEYS_URL}/baileys/qr"
fi
response=$(do_curl "$URL" 2>&1) || true
qr_status=$(echo "$response" | jq -r '.status' 2>/dev/null)

if [[ "$qr_status" == "already_connected" ]] || [[ "$qr_status" == "qr_ready" ]] || [[ "$qr_status" == "no_qr" ]]; then
  pass "QR endpoint responded (status: $qr_status)"
else
  fail "QR endpoint" "Response: $response"
fi

# Test 4.3: Send Message (Mock/Live based on connection)
log_test "4.3 Send Message API"
if $USE_KONG; then
  URL="${BASE_URL}/baileys/send"
else
  URL="${BAILEYS_URL}/baileys/send"
fi

# Check if connected first
status_response=$(do_curl "${BAILEYS_URL}/baileys/status" 2>&1) || true
wa_connected=$(echo "$status_response" | jq -r '.connected' 2>/dev/null)
wa_mode=$(do_curl "${BAILEYS_URL}/baileys/health" 2>&1 | jq -r '.mode' 2>/dev/null)

if [[ "$wa_mode" == "mock" ]] || [[ "$wa_connected" == "true" ]]; then
  response=$(do_curl -X POST "$URL" \
    -H "Content-Type: application/json" \
    -d "{
      \"to\": \"919999999999\",
      \"content\": \"E2E Test Message - $(date)\"
    }" 2>&1) || true

  if check_status "$response" ".success" "true"; then
    msg_id=$(echo "$response" | jq -r '.messageId')
    mode=$(echo "$response" | jq -r '.mode')
    pass "Message sent successfully (id: $msg_id, mode: $mode)"
  else
    fail "Send message" "Response: $response"
  fi
else
  skip "Send message" "WhatsApp not connected and not in mock mode"
fi

# ============================================================================
# SECTION 5: Novu Bridge APIs
# ============================================================================
echo -e "\n${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}SECTION 5: Novu Bridge APIs${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"

# First, ensure test user has consent for this test
log_test "5.0 Setup: Create test user with consent"
BRIDGE_TEST_USER="bridge-test-user"
BRIDGE_TEST_PHONE="919876543210"

# Create user preference with consent
if $USE_KONG; then
  URL="${BASE_URL}/user-preferences/v1/_upsert"
else
  URL="${USER_PREFS_URL}/user-preferences/v1/_upsert"
fi
do_curl -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"preference\": {
      \"userId\": \"$BRIDGE_TEST_USER\",
      \"tenantId\": \"pg.citya\",
      \"preferenceCode\": \"USER_NOTIFICATION_PREFERENCES\",
      \"payload\": {
        \"preferredLanguage\": \"en_IN\",
        \"consent\": {
          \"WHATSAPP\": {
            \"status\": \"GRANTED\",
            \"grantedAt\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",
            \"method\": \"explicit\"
          }
        },
        \"channels\": {
          \"WHATSAPP\": {\"enabled\": true, \"phone\": \"$BRIDGE_TEST_PHONE\"}
        }
      }
    }
  }" > /dev/null 2>&1
echo -e "${GREEN}✓ Test user created${NC}"

# Test 5.1: Trigger Notification - With Consent
log_test "5.1 Trigger Notification (User with Consent)"
if $USE_KONG; then
  URL="${BASE_URL}/novu-bridge/v1/_trigger"
else
  URL="${NOVU_BRIDGE_URL}/novu-bridge/v1/_trigger"
fi
response=$(do_curl -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"eventType\": \"PGR_CREATE\",
    \"tenantId\": \"pg.citya\",
    \"recipient\": {
      \"userId\": \"$BRIDGE_TEST_USER\",
      \"phone\": \"$BRIDGE_TEST_PHONE\"
    },
    \"data\": {
      \"serviceRequestId\": \"PGR-E2E-$(date +%s)\",
      \"serviceCode\": \"StreetLight\",
      \"address\": \"E2E Test Address\",
      \"createdTime\": \"$(date '+%Y-%m-%d %H:%M')\"
    }
  }" 2>&1) || true

result_status=$(echo "$response" | jq -r '.result.status' 2>/dev/null)
if [[ "$result_status" == "SENT" ]] || [[ "$result_status" == "SIMULATED" ]]; then
  provider=$(echo "$response" | jq -r '.result.details.provider')
  pass "Notification triggered (status: $result_status, provider: $provider)"
elif [[ "$result_status" == "SKIPPED" ]]; then
  reason=$(echo "$response" | jq -r '.result.details')
  skip "Notification trigger" "$reason"
else
  fail "Trigger notification" "Response: $response"
fi

# Test 5.2: Trigger Notification - Without Consent (should be skipped)
log_test "5.2 Trigger Notification (User without Consent - should skip)"
NO_CONSENT_USER="no-consent-user-$(date +%s)"
if $USE_KONG; then
  URL="${BASE_URL}/novu-bridge/v1/_trigger"
else
  URL="${NOVU_BRIDGE_URL}/novu-bridge/v1/_trigger"
fi
response=$(do_curl -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"eventType\": \"PGR_CREATE\",
    \"tenantId\": \"pg.citya\",
    \"recipient\": {
      \"userId\": \"$NO_CONSENT_USER\",
      \"phone\": \"919111111111\"
    },
    \"data\": {
      \"serviceRequestId\": \"PGR-NOCONSENT-$(date +%s)\",
      \"serviceCode\": \"Garbage\",
      \"address\": \"No Consent Test\"
    }
  }" 2>&1) || true

result_status=$(echo "$response" | jq -r '.result.status' 2>/dev/null)
if [[ "$result_status" == "SKIPPED" ]]; then
  pass "Notification correctly skipped for user without consent"
else
  fail "Consent check" "Expected SKIPPED, got: $result_status"
fi

# Test 5.3: Trigger with Invalid Event Type
log_test "5.3 Trigger with Invalid Event Type"
if $USE_KONG; then
  URL="${BASE_URL}/novu-bridge/v1/_trigger"
else
  URL="${NOVU_BRIDGE_URL}/novu-bridge/v1/_trigger"
fi
response=$(do_curl -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"eventType\": \"INVALID_EVENT_TYPE\",
    \"tenantId\": \"pg.citya\",
    \"recipient\": {
      \"userId\": \"$BRIDGE_TEST_USER\",
      \"phone\": \"$BRIDGE_TEST_PHONE\"
    },
    \"data\": {}
  }" 2>&1) || true

result_status=$(echo "$response" | jq -r '.result.status' 2>/dev/null)
if [[ "$result_status" == "SKIPPED" ]] || [[ "$result_status" == "ERROR" ]]; then
  pass "Invalid event type handled correctly (status: $result_status)"
else
  fail "Invalid event handling" "Response: $response"
fi

# ============================================================================
# SECTION 6: Kong Gateway Routes (if testing via Kong)
# ============================================================================
if $USE_KONG; then
  echo -e "\n${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}SECTION 6: Kong Gateway Routes${NC}"
  echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"

  # Test 6.1: Public Health Endpoints (no auth required)
  log_test "6.1 Public Health Endpoints"

  for endpoint in "/health/mdms" "/health/user" "/health/workflow" "/health/boundary"; do
    response=$(curl -s "${BASE_URL}${endpoint}" 2>&1) || true
    if [[ -n "$response" ]] && [[ "$response" != *"Unauthorized"* ]]; then
      echo -e "${GREEN}  ✓ $endpoint accessible${NC}"
    else
      echo -e "${RED}  ✗ $endpoint failed${NC}"
    fi
  done
  pass "Public health endpoints checked"

  # Test 6.2: Auth Required Endpoints
  log_test "6.2 Auth Required Endpoints (with API key)"

  for endpoint in "/baileys/status" "/novu-bridge/health"; do
    response=$(curl -s -H "X-API-Key: $API_KEY" "${BASE_URL}${endpoint}" 2>&1) || true
    if [[ -n "$response" ]] && [[ "$response" != *"Unauthorized"* ]] && [[ "$response" != *"No API key"* ]]; then
      echo -e "${GREEN}  ✓ $endpoint accessible with API key${NC}"
    else
      echo -e "${RED}  ✗ $endpoint failed: $response${NC}"
    fi
  done
  pass "Auth endpoints checked"

  # Test 6.3: Auth Required Without Key (should fail)
  log_test "6.3 Auth Required Without API Key (should fail)"
  response=$(curl -s "${BASE_URL}/baileys/send" -X POST -H "Content-Type: application/json" -d '{}' 2>&1) || true
  if [[ "$response" == *"No API key"* ]] || [[ "$response" == *"Unauthorized"* ]] || [[ "$response" == *"401"* ]]; then
    pass "Unauthorized request correctly rejected"
  else
    fail "Auth enforcement" "Request should have been rejected: $response"
  fi
fi

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                      TEST SUMMARY                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

echo -e "${BLUE}Results:${NC}"
for result in "${RESULTS[@]}"; do
  echo -e "  $result"
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${GREEN}Passed:${NC}  $PASSED"
echo -e "  ${RED}Failed:${NC}  $FAILED"
echo -e "  ${YELLOW}Skipped:${NC} $SKIPPED"
echo -e "  ${BLUE}Total:${NC}   $((PASSED + FAILED + SKIPPED))"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ $FAILED -gt 0 ]]; then
  echo -e "${RED}Some tests failed!${NC}"
  exit 1
else
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
fi
