#!/bin/bash
# =============================================================================
# GlassFish JDBC, JMS & Custom Resource Setup (Generic Template)
# =============================================================================
# Creates the JDBC connection pool, JDBC resource, and application custom
# resources (JNDI) required by the application. Optionally creates JMS
# resources (uncomment the JMS section below if needed).
#
# Run once per GlassFish server (or with --delete to recreate after
# config changes). Idempotent — safe to run multiple times.
#
# Usage:
#   ./setup-glassfish-resources.sh <db.properties> <env.properties>
#   ./setup-glassfish-resources.sh <db.properties> <env.properties> --delete
#
# The db.properties file must contain:
#   db.host, db.port, db.name, db.user, db.password
#
# The env.properties file contains application config values as key=value
# pairs. Each key becomes a JNDI custom resource under the configured prefix.
# See env.properties.sample for the expected format.
#
# The --delete flag tears down existing resources before recreating them.
#
# IMPORTANT: Both properties files contain secrets (DB password, API keys).
# Secure them before running this script:
#   chmod 600 db.properties env.properties
# =============================================================================

set -euo pipefail

# ─── Configuration (edit these for your project) ─────────────────────────────

ASADMIN="${ASADMIN:-asadmin}"
JNDI_PREFIX="app"                          # JNDI namespace prefix for custom resources

JDBC_POOL="jdbc/AppConnPool"               # JDBC connection pool name
JDBC_RESOURCE="jdbc/AppDataSource"         # JDBC resource (datasource) name
DB_DRIVER_CLASS="org.postgresql.Driver"    # JDBC driver class
DB_DS_CLASS="org.postgresql.ds.PGConnectionPoolDataSource"  # DataSource class

# Pool tuning
POOL_STEADY=8
POOL_MAX=32
POOL_RESIZE=2
POOL_IDLE_TIMEOUT=300

# ─── Parse arguments ─────────────────────────────────────────────────────────

PROPS_FILE="${1:?Usage: $0 <db.properties> <env.properties> [--delete]}"
ENV_FILE="${2:?Usage: $0 <db.properties> <env.properties> [--delete]}"
DELETE_FIRST="${3:-}"

if [ ! -f "$PROPS_FILE" ]; then
    echo "Error: File not found: $PROPS_FILE"
    exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: File not found: $ENV_FILE"
    exit 1
fi

# ─── Helpers ─────────────────────────────────────────────────────────────────

# Warn if properties files are world-readable (they contain secrets)
check_permissions() {
    local file="$1"
    local perms
    perms=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%Lp" "$file" 2>/dev/null) || return 0
    if [ "${perms: -1}" != "0" ] || [ "${perms: -2:1}" != "0" ]; then
        echo "WARNING: $file is readable by group or others (mode $perms)."
        echo "         This file contains secrets. Run: chmod 600 $file"
        echo ""
    fi
}

# Read a property from db.properties
get_prop() {
    grep "^$1=" "$PROPS_FILE" | cut -d'=' -f2- | xargs || true
}

# Check if a GlassFish resource already exists
resource_exists() {
    local list_cmd="$1"
    local name="$2"
    $ASADMIN "$list_cmd" 2>/dev/null | grep -q "^${name}$"
}

# ─── Validate inputs ────────────────────────────────────────────────────────

check_permissions "$PROPS_FILE"
check_permissions "$ENV_FILE"

DB_HOST=$(get_prop "db.host")
DB_PORT=$(get_prop "db.port")
DB_NAME=$(get_prop "db.name")
DB_USER=$(get_prop "db.user")
DB_PASSWORD=$(get_prop "db.password")

if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
    echo "Error: db.properties must contain db.name, db.user, and db.password"
    exit 1
fi

# ─── Delete existing resources (if --delete) ─────────────────────────────────

if [ "$DELETE_FIRST" = "--delete" ]; then
    echo "=== Deleting existing resources ==="

    echo "Deleting JDBC resource: $JDBC_RESOURCE"
    $ASADMIN delete-jdbc-resource "$JDBC_RESOURCE" 2>/dev/null || true

    echo "Deleting JDBC connection pool: $JDBC_POOL"
    $ASADMIN delete-jdbc-connection-pool "$JDBC_POOL" 2>/dev/null || true

    # Uncomment if using JMS:
    # echo "Deleting JMS resources..."
    # $ASADMIN delete-jms-resource "jms/YourQueue" 2>/dev/null || true
    # $ASADMIN delete-jms-resource "jms/YourConnectionFactory" 2>/dev/null || true

    echo ""
    echo "Deleting custom resources (${JNDI_PREFIX}/*)..."
    while IFS='=' read -r key _; do
        [[ -z "$key" || "$key" == \#* ]] && continue
        key=$(echo "$key" | xargs)
        $ASADMIN delete-custom-resource "${JNDI_PREFIX}/${key}" 2>/dev/null || true
    done < "$ENV_FILE"

    echo ""
fi

# ─── Create JDBC resources ───────────────────────────────────────────────────

echo "=== Creating JDBC resources ==="

if resource_exists list-jdbc-connection-pools "$JDBC_POOL"; then
    echo "JDBC connection pool already exists: $JDBC_POOL"
else
    echo "Creating JDBC connection pool: $JDBC_POOL"
    $ASADMIN create-jdbc-connection-pool \
        --datasourceclassname "$DB_DS_CLASS" \
        --driverclassname "$DB_DRIVER_CLASS" \
        --restype javax.sql.ConnectionPoolDataSource \
        --steadypoolsize "$POOL_STEADY" \
        --maxpoolsize "$POOL_MAX" \
        --poolresize "$POOL_RESIZE" \
        --idletimeout "$POOL_IDLE_TIMEOUT" \
        --isconnectvalidatereq true \
        --validationmethod auto-commit \
        --failconnection true \
        --property "databaseName=${DB_NAME}:user=${DB_USER}${DB_PASSWORD:+:password=${DB_PASSWORD}}${DB_HOST:+:serverName=${DB_HOST}}${DB_PORT:+:port=${DB_PORT}}" \
        "$JDBC_POOL"
fi

if resource_exists list-jdbc-resources "$JDBC_RESOURCE"; then
    echo "JDBC resource already exists: $JDBC_RESOURCE"
else
    echo "Creating JDBC resource: $JDBC_RESOURCE"
    $ASADMIN create-jdbc-resource \
        --connectionpoolid "$JDBC_POOL" \
        "$JDBC_RESOURCE"
fi

echo "Pinging connection pool..."
$ASADMIN ping-connection-pool "$JDBC_POOL"

# ─── Create JMS resources (uncomment if needed) ──────────────────────────────

# Uncomment this section if your application uses JMS queues/topics.
#
# JMS_CONN_FACTORY="jms/YourConnectionFactory"
# JMS_QUEUE="jms/YourQueue"
#
# echo ""
# echo "=== Creating JMS resources ==="
#
# if resource_exists list-jms-resources "$JMS_CONN_FACTORY"; then
#     echo "JMS connection factory already exists: $JMS_CONN_FACTORY"
# else
#     echo "Creating JMS connection factory: $JMS_CONN_FACTORY"
#     $ASADMIN create-jms-resource \
#         --restype jakarta.jms.ConnectionFactory \
#         --property "imqRedeliveryAttempts=5" \
#         "$JMS_CONN_FACTORY"
# fi
#
# if resource_exists list-jms-resources "$JMS_QUEUE"; then
#     echo "JMS queue already exists: $JMS_QUEUE"
# else
#     echo "Creating JMS queue: $JMS_QUEUE"
#     $ASADMIN create-jms-resource \
#         --restype jakarta.jms.Queue \
#         --property "Name=YourQueue" \
#         "$JMS_QUEUE"
# fi

# ─── Create custom resources (application config) ────────────────────────────

echo ""
echo "=== Creating custom resources from $ENV_FILE ==="

while IFS='=' read -r key value; do
    # Skip blank lines and comments
    [[ -z "$key" || "$key" == \#* ]] && continue

    # Trim whitespace
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs)

    jndi_name="${JNDI_PREFIX}/${key}"

    if $ASADMIN list-custom-resources 2>/dev/null | grep -q "^${jndi_name}$"; then
        echo "Already exists: $jndi_name"
        continue
    fi

    # Escape colons and backslashes for asadmin property syntax
    escaped_value="${value//\\/\\\\}"
    escaped_value="${escaped_value//:/\\:}"

    echo "Creating: $jndi_name"
    $ASADMIN create-custom-resource \
        --restype=java.lang.String \
        --factoryclass=org.glassfish.resources.custom.factory.PrimitivesAndStringFactory \
        --property "value=$escaped_value" \
        "$jndi_name"

done < "$ENV_FILE"

# ─── Add JVM options for OOM heap dump ────────────────────────────────────────

echo ""
echo "=== Configuring JVM heap dump on OOM ==="

# Remove existing options first (idempotent — ignore errors if not present)
$ASADMIN delete-jvm-options -- "-XX\:+HeapDumpOnOutOfMemoryError" 2>/dev/null || true
$ASADMIN delete-jvm-options -- "-XX\:HeapDumpPath=/tmp/glassfish-heapdump.hprof" 2>/dev/null || true

$ASADMIN create-jvm-options -- "-XX\:+HeapDumpOnOutOfMemoryError"
$ASADMIN create-jvm-options -- "-XX\:HeapDumpPath=/tmp/glassfish-heapdump.hprof"

echo ""
echo "=== Done. All resources have been configured. ==="
