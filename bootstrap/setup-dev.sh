#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="local-dev-x"
APP_NAME_DIRECT="go-web-app-direct"
APP_NAME_DOCKER="go-web-app-docker"

export ZITADEL_ISSUER
export ZITADEL_TOKEN="$(cat "$ZITADEL_TOKEN_FILE")"
export TARGET_DIR="${TARGET_DIR:-./secrets}"

echo "🔐 ZITADEL bootstrap starting..."
echo "🌐 Using ZITADEL at: $ZITADEL_ISSUER"

# Wait for ZITADEL to be ready
echo "⏳ Waiting for ZITADEL to be ready..."
for i in {1..30}; do
  if curl -sf "$ZITADEL_ISSUER/debug/healthz" > /dev/null; then
    echo "✅ ZITADEL is ready!"
    break
  fi
  if [ $i -eq 30 ]; then
    echo "❌ ZITADEL failed to become ready"
    exit 1
  fi
  sleep 2
done

# Function to make API calls
api_call() {
  local method=$1
  local endpoint=$2
  local data=${3:-}

  echo "   Making API call: $method $ZITADEL_ISSUER/$endpoint" >> log.txt
  echo "   Data: $data" >> log.txt

  curl --fail -X "$method" \
    "$ZITADEL_ISSUER/$endpoint" \
    -H "Authorization: Bearer $ZITADEL_TOKEN" \
    -H "Content-Type: application/json" \
    -H 'Accept: application/json' \
    ${data:+-d "$data"} 2>> log.txt
}

# ---------------------------
# Get org ID
ORG_ID=$(api_call POST "zitadel.org.v2beta.OrganizationService/ListOrganizations" '{"filter": [{"nameFilter": {"name": "'$ZITADEL_ORG'", "method": "TEXT_QUERY_METHOD_EQUALS"}}]}' | jq -r '.organizations[0].id // empty')
ORG_DOMAIN=$(api_call POST "zitadel.org.v2beta.OrganizationService/ListOrganizations" '{"filter": [{"nameFilter": {"name": "'$ZITADEL_ORG'", "method": "TEXT_QUERY_METHOD_EQUALS"}}]}' | jq -r '.organizations[0].primaryDomain // empty')

if [[ -z "$ORG_ID" ]]; then
  echo "❌ Failed to retrieve organization ID for $ZITADEL_ORG"
  exit 1
fi
echo "org id: $ORG_ID - primaryDomain: $ORG_DOMAIN"

# ----------------------------
# Project
# ----------------------------
echo "🔍 Checking for existing project: $PROJECT_NAME"
PROJECT_JSON=$(api_call POST "zitadel.project.v2.ProjectService/ListProjects" '{"filters": [{"projectNameFilter": {"projectName": "'$PROJECT_NAME'","method": "TEXT_FILTER_METHOD_EQUALS"}}]}')
PROJECT_ID=$(echo "$PROJECT_JSON" | jq -r '.projects[0].projectId // empty')

if [[ -z "$PROJECT_ID" ]]; then
  echo "➕ Creating project: $PROJECT_NAME"
  PROJECT_JSON=$(api_call POST "zitadel.project.v2.ProjectService/CreateProject" "{\"name\": \"$PROJECT_NAME\", \"organizationId\": \"$ORG_ID\"}")
  PROJECT_ID=$(echo "$PROJECT_JSON" | jq -r '.projectId // empty')
  if [[ -z "$PROJECT_ID" ]]; then
    echo "   Error creating project. Response: $PROJECT_JSON"
    exit 1
  fi
  echo "   Created with ID: $PROJECT_ID"
else
  echo "✅ Project exists with ID: $PROJECT_ID"
fi

# ----------------------------
# OIDC Apps - Function to create or get app
# ----------------------------
create_or_get_app() {
  local app_name=$1
  local redirect_uri=$2
  local allowedOrigins=$3
  local deployment_type=$4

  echo "🔍 Checking for existing app: $app_name"
  local apps_json; apps_json=$(api_call POST "zitadel.application.v2.ApplicationService/ListApplications" '{"filters": [{"projectIdFilter": {"projectId": "'"$PROJECT_ID"'"}},{"nameFilter": {"name": "'"$app_name"'", "method": "TEXT_FILTER_METHOD_EQUALS"}}]}')
  local app_id; app_id=$(echo "$apps_json" | jq -r '.applications[0].applicationId // empty')

  if [[ -z "$app_id" ]]; then
    echo "➕ Creating OIDC app: $app_name ($deployment_type)"
    local app_json; app_json=$(api_call POST "zitadel.application.v2.ApplicationService/CreateApplication" '{
      "projectId": "'$PROJECT_ID'",
      "name": "'"$app_name"'",
      "oidcConfiguration": {
        "redirectUris": [
          "'$redirect_uri'"
        ],
        "responseTypes": [
          "OIDC_RESPONSE_TYPE_CODE"
        ],
        "grantTypes": [
          "OIDC_GRANT_TYPE_AUTHORIZATION_CODE"
        ],
        "appType": "OIDC_APP_TYPE_WEB",
        "authMethodType": "OIDC_AUTH_METHOD_TYPE_NONE",
        "developmentMode": true,
        "allowedOrigins": [
          "'"$allowedOrigins"'"
        ],
        "postLogoutRedirectUris": [
          "'"$allowedOrigins"'"
        ],
        "loginVersion": {
          "loginV2": {
            "baseUri": ""
          }
        }
      }
    }')

    echo "$app_json"
    local app_id; app_id=$(echo "$app_json" | jq -r '.applicationId // empty')
    local client_id; client_id=$(echo "$app_json" | jq -r '.oidcConfiguration.clientId // empty')

    if [[ -z "$client_id" ]]; then
      echo "   ❌ Error creating OIDC app. Response: $app_json"
      exit 1
    fi

    echo "   Created with Client ID: $client_id"
  else
    echo "✅ App exists with ID: $app_id"
    # Get app details
  fi

  local app_json; app_json=$(api_call POST "zitadel.application.v2.ApplicationService/GetApplication" '{"applicationId": "'$app_id'"}')
  local client_id; client_id=$(echo "$app_json" | jq -r '.application.oidcConfiguration.clientId')

  echo "   Writing app details to $TARGET_DIR/$deployment_type-client.json"
  echo "$app_json" | jq '.' > $TARGET_DIR/$deployment_type-client.json

  # write to file
  echo "   Writing credentials to $TARGET_DIR/$deployment_type-client.yaml"
  cat > $TARGET_DIR/$deployment_type-client.yaml <<EOF
# ZITADEL OIDC Configuration for $deployment_type deployment
# Generated by bootstrap script at $(date)
client_id: "$client_id"
redirect_url: "$redirect_uri"
issuer: "$ZITADEL_ISSUER"
EOF
}

# Create secrets directory
mkdir -p $TARGET_DIR


# Create both apps
create_or_get_app "$APP_NAME_DIRECT" "http://localhost:8091/auth/callback" "http://localhost:8091/" "direct"
create_or_get_app "$APP_NAME_DOCKER" "http://localhost:8090/auth/callback" "http://localhost:8090/" "docker"


# Write test users config
echo "📝 Writing test users configuration..."
cat > $TARGET_DIR/test-users.yaml <<EOF
# Test Users for ZITADEL Demo
# Generated by bootstrap script at $(date)
test_users:
EOF


# Verify files were created
if [[ -f $TARGET_DIR/docker-client.yaml ]] && [[ -f $TARGET_DIR/direct-client.yaml ]] && [[ -f $TARGET_DIR/test-users.yaml ]]; then
  echo "✅ Configuration files written:"
  echo "   📄 .env (environment variables)"
  echo "   📄 $TARGET_DIR/docker-client.yaml"
  echo "   📄 $TARGET_DIR/direct-client.yaml"
  echo "   📄 $TARGET_DIR/test-users.yaml (test user credentials)"
else
  echo "⚠️  Failed to write one or more configuration files"
  exit 1
fi
echo ""

# ----------------------------
# Users
# ----------------------------
create_user() {
  local username=$1
  local email=$2
  local first=$3
  local last=$4

  echo "🔍 Checking for existing user: $username"

  # Check if user exists
  USER_JSON=$(api_call POST "v2/users" '{"queries": [{"userNameQuery": {"userName": "'"$username"'", "method": "TEXT_QUERY_METHOD_EQUALS"}}]}')
  USER_ID=$(echo "$USER_JSON" | jq -r '.result[0].userId // empty')

  if [[ -n "$USER_ID" ]]; then
    echo "✅ User exists: $username (ID: $USER_ID)"
  else
    echo "➕ Creating user: $username"
    USER_JSON=$(api_call POST "v2/users/new" "{
      \"organizationId\": \"$ORG_ID\",
      \"username\": \"$username\",
      \"human\": {
        \"profile\": {
          \"givenName\": \"$first\",
          \"familyName\": \"$last\"
        },
        \"email\": {
          \"email\": \"$email\",
          \"isVerified\": true
        },
        \"password\": {
          \"password\": \"Password1!\",
          \"changeRequired\": false
        }
      }
    }")
    USER_ID=$(echo "$USER_JSON" | jq -r '.id')
    echo "   Created with ID: $USER_ID"

  fi
}

# Create users in the default organization (not as initial/setup users)
create_user alice@example.com alice@example.com Alice Dev
create_user bob@example.com bob@example.com Bob Tester

# Add users that were created
for user in alice bob; do
  case $user in
    alice)
      display_name="Alice Dev"
      email="alice@example.com"
      ;;
    bob)
      display_name="Bob Tester"
      email="bob@example.com"
      ;;
  esac

  cat >> $TARGET_DIR/test-users.yaml <<EOF
  - username: "$user"
    email: "$email"
    password: "Password1!"
    login_name: "$email"
    display_name: "$display_name"
EOF
done


echo ""
echo "📋 Login Instructions:"
echo "   ℹ️  These are regular organization users, not initial setup users"
echo "   🔐 Login format: email"
echo "   👤 Available users: alice@example.com, bob@example.com"
echo "   🔑 Password: Password1!"

echo ""
echo "✅ ZITADEL bootstrap complete!"
echo "🌐 Console URL: $ZITADEL_ISSUER/ui/console"
echo "Login with admin: $ZITADEL_ISSUER/ui/console?login_hint=zitadel-admin@$ORG_DOMAIN"
echo "🔐 Default org : $ZITADEL_ORG"