#!/usr/bin/env bash
#
# gf — GlassFish dev workflow CLI
#
# Setup:
#   Add GlassFish bin/ to PATH, then:
#   ./gf run          # start server + build + deploy
#
# Quick start:
#   ./gf run          # start server + build + deploy
#   ./gf sync -v      # after code changes (UI + hot-swap)
#   ./gf log --err    # tail error logs
#
# Run ./gf --help for full command reference.

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Auto-detect GlassFish from PATH
if ! command -v asadmin &>/dev/null; then
    echo "asadmin not found on PATH." >&2
    echo "  Add GlassFish bin/ to your shell profile:" >&2
    echo "    Linux (~/.bashrc):  export PATH=\"/path/to/glassfish8/bin:\$PATH\"" >&2
    echo "    macOS (~/.zshrc):   export PATH=\"/path/to/glassfish8/bin:\$PATH\"" >&2
    exit 1
fi
ASADMIN="$(command -v asadmin)"
GF_BASE="$(dirname "$(dirname "$ASADMIN")")/glassfish"

# Overridable via environment variables
DOMAIN_NAME="${GF_DOMAIN:-domain1}"
CONTEXT_ROOT="${GF_CONTEXT_ROOT:-/}"
DEBUG_PORT="${GF_DEBUG_PORT:-9009}"

GF_DOMAIN_DIR="$GF_BASE/domains/$DOMAIN_NAME"
LOG_FILE="$GF_DOMAIN_DIR/logs/server.log"
WEBAPP_SRC="$PROJECT_DIR/src/main/webapp"
JAVA_SOURCE_DIR="$PROJECT_DIR/src/main/java"
CLASSES_DIR="$PROJECT_DIR/target/classes"
CLASSPATH_CACHE="$PROJECT_DIR/tools/.classpath.cache"
LAST_COMPILE_MARKER="$PROJECT_DIR/target/.last-compile"

# Auto-detect mvnw or mvn
if [[ -x "$PROJECT_DIR/mvnw" ]]; then
    MVNW="$PROJECT_DIR/mvnw"
elif command -v mvn &>/dev/null; then
    MVNW="mvn"
else
    echo "Neither ./mvnw nor mvn found." >&2
    exit 1
fi

# ─── Colors ───────────────────────────────────────────────────────────────────

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m' # No Color

# ─── Helpers ──────────────────────────────────────────────────────────────────

info()    { printf '%b\n' "${CYAN}▶${NC} $*"; }
success() { printf '%b\n' "${GREEN}✔${NC} $*"; }
warn()    { printf '%b\n' "${YELLOW}⚠${NC} $*"; }
error()   { printf '%b\n' "${RED}✖${NC} $*" >&2; }

# Time tracking: returns current epoch in milliseconds.
# macOS BSD date lacks %N; fall back to perl (ships with macOS, Time::HiRes is core).
now_ms() {
    if [[ "$OSTYPE" == darwin* ]]; then
        perl -MTime::HiRes=gettimeofday -e '($s,$us)=gettimeofday;printf "%d%03d\n",$s,int($us/1000)'
    else
        date +%s%3N
    fi
}

# Prints elapsed time since a given epoch millis, e.g. "(3.2s)"
elapsed() {
    local start_ms=$1
    local end_ms
    end_ms=$(now_ms)
    local diff_ms=$(( end_ms - start_ms ))
    local secs=$(( diff_ms / 1000 ))
    local frac=$(( (diff_ms % 1000) / 100 ))
    printf '(%d.%ds)' "$secs" "$frac"
}

# Detect Java version from pom.xml (maven.compiler.release or maven.compiler.source).
detect_java_version() {
    local version
    version=$(sed -n 's/.*<maven\.compiler\.release>\([^<]*\)<.*/\1/p' "$PROJECT_DIR/pom.xml" 2>/dev/null | head -1)
    if [[ -z "$version" ]]; then
        version=$(sed -n 's/.*<maven\.compiler\.source>\([^<]*\)<.*/\1/p' "$PROJECT_DIR/pom.xml" 2>/dev/null | head -1)
    fi
    echo "$version"
}

# Ensure domain.xml has correct JDWP debug-options.
# Fixes server=n (should be y) and suspend=y (should be n) which prevent startup.
ensure_debug_options() {
    local domain_xml="$GF_DOMAIN_DIR/config/domain.xml"
    [[ -f "$domain_xml" ]] || return 0

    local correct_opts="-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:${DEBUG_PORT}"

    # Only fix lines that have server=n or suspend=y (broken config)
    if grep -q 'debug-options="[^"]*server=n\|debug-options="[^"]*suspend=y' "$domain_xml"; then
        info "Fixing JDWP debug-options in domain.xml (server=n→y, suspend=y→n)..."
        # Cross-platform sed: write to temp file instead of -i (macOS vs Linux differences)
        local tmp="${domain_xml}.tmp"
        sed -E '/server=n|suspend=y/s/debug-options="-agentlib:jdwp=[^"]*"/debug-options="'"$correct_opts"'"/' \
            "$domain_xml" > "$tmp" && mv "$tmp" "$domain_xml"
        success "Debug options fixed."
    fi
}

# Build or refresh the javac classpath cache.
# Re-generates when pom.xml is newer than the cache file.
ensure_classpath_cache() {
    if [[ -f "$CLASSPATH_CACHE" ]] && [[ ! "$PROJECT_DIR/pom.xml" -nt "$CLASSPATH_CACHE" ]]; then
        return 0
    fi
    info "Caching classpath (pom.xml changed or first run)..."
    cd "$PROJECT_DIR"
    "$MVNW" dependency:build-classpath -Dmdep.outputFile="$CLASSPATH_CACHE" -q
    success "Classpath cached."
}

# Find .java files modified since the last successful incremental compile.
# Returns 1 if no marker exists or no changed files found.
find_changed_java_files() {
    if [[ ! -f "$LAST_COMPILE_MARKER" ]]; then
        return 1
    fi
    local changed
    changed=$(find "$JAVA_SOURCE_DIR" -name '*.java' -newer "$LAST_COMPILE_MARKER" -type f)
    if [[ -z "$changed" ]]; then
        return 1
    fi
    echo "$changed"
    return 0
}

# Find the WAR file in the target directory.
find_war_file() {
    local war
    war=$(find "$PROJECT_DIR/target" -maxdepth 1 -name '*.war' -type f | head -1)
    if [[ -z "$war" ]]; then
        error "No WAR file found in target/. Run: $MVNW package"
        exit 1
    fi
    echo "$war"
}

# Auto-detect the deployed app name.
# Step 1: scan the exploded applications directory (skips GlassFish internals).
# Step 2 (fallback): query asadmin for domain.xml-only ("ghost") registrations.
find_app_name() {
    local app_dir="$GF_DOMAIN_DIR/applications"
    if [[ -d "$app_dir" ]]; then
        for dir in "$app_dir"/*/; do
            local name
            name="$(basename "$dir")"
            if [[ "$name" != "__internal" && "$name" != "ejb-timer-service-app" ]]; then
                echo "$name"
                return 0
            fi
        done
    fi

    # Fallback: ask GlassFish directly (handles domain.xml-only registrations)
    local app
    app=$("$ASADMIN" list-applications 2>/dev/null \
        | grep -v -E '^(Command|Nothing|$)' \
        | awk '{print $1}' | head -1)
    if [[ -n "$app" ]]; then
        echo "$app"
        return 0
    fi

    return 1
}

# Find the exploded deployment directory under the domain.
find_exploded_dir() {
    local app_name
    app_name="$(find_app_name)" || return 1
    local exploded="$GF_DOMAIN_DIR/applications/$app_name"
    if [[ -d "$exploded" ]]; then
        echo "$exploded"
        return 0
    fi
    return 1
}

# Check if the domain is running.
is_domain_running() {
    "$ASADMIN" list-domains 2>/dev/null | grep -q "$DOMAIN_NAME running"
}

# Check if the app is deployed.
is_app_deployed() {
    find_app_name &>/dev/null
}

require_running() {
    if ! is_domain_running; then
        error "GlassFish domain '${DOMAIN_NAME}' is not running."
        echo "  Run: $0 start"
        exit 1
    fi
}

require_deployed() {
    if ! is_app_deployed; then
        error "No application is deployed."
        echo "  Run: $0 deploy"
        exit 1
    fi
}

sync_ui_files() {
    local exploded="$1"
    rsync -a --delete \
        --include='*.xhtml' --include='*.css' --include='*.js' \
        --include='*.html' --include='*.png' --include='*.jpg' \
        --include='*.gif' --include='*.svg' --include='*.ico' \
        --include='*/' --exclude='*' \
        "$WEBAPP_SRC/" "$exploded/" >/dev/null 2>&1
}

sync_resource_files() {
    local exploded="$1"
    rsync -a --delete \
        --include='*.jrxml' \
        --include='*/' --exclude='*' \
        "$PROJECT_DIR/src/main/resources/reports/" "$exploded/WEB-INF/classes/reports/" >/dev/null 2>&1
}

# ─── Commands ─────────────────────────────────────────────────────────────────

cmd_start() {
    local debug="true"
    if [[ "${1:-}" == "--no-debug" ]]; then
        debug="false"
    fi

    if is_domain_running; then
        warn "Domain '${DOMAIN_NAME}' is already running."
        return 0
    fi

    local start_rc=0
    if [[ "$debug" == "true" ]]; then
        ensure_debug_options
        info "Starting GlassFish domain '${DOMAIN_NAME}' in ${BOLD}debug mode${NC} (port 9009)..."
        "$ASADMIN" start-domain --debug=true "$DOMAIN_NAME" || start_rc=$?
    else
        info "Starting GlassFish domain '${DOMAIN_NAME}'..."
        "$ASADMIN" start-domain "$DOMAIN_NAME" || start_rc=$?
    fi

    if [[ $start_rc -ne 0 ]]; then
        # asadmin may timeout but the domain could still be starting — verify
        warn "asadmin exited with code ${start_rc}. Checking if domain came up..."
        local retries=6
        for ((i=1; i<=retries; i++)); do
            if is_domain_running; then
                success "Domain started (took longer than asadmin timeout)."
                return 0
            fi
            info "Waiting for domain... (${i}/${retries})"
            sleep 10
        done
        error "Domain failed to start. Check the server log:"
        echo "  $0 log"
        exit 1
    fi

    success "Domain started."
}

cmd_stop() {
    if ! is_domain_running; then
        warn "Domain '${DOMAIN_NAME}' is not running."
        return 0
    fi

    info "Stopping GlassFish domain '${DOMAIN_NAME}'..."
    "$ASADMIN" stop-domain "$DOMAIN_NAME"
    success "Domain stopped."
}

cmd_deploy() {
    require_running

    info "Building WAR..."
    cd "$PROJECT_DIR"
    "$MVNW" clean package -DskipTests -q
    local war_file
    war_file="$(find_war_file)"
    success "WAR built: ${war_file}"

    # Undeploy first for cleaner classloader release (avoids GlassFish 8 heap leak from --force)
    local app_name
    if app_name="$(find_app_name)"; then
        info "Undeploying '${app_name}' first..."
        "$ASADMIN" undeploy "$app_name" 2>/dev/null || true
    fi

    info "Deploying to GlassFish..."
    "$ASADMIN" deploy --contextroot "$CONTEXT_ROOT" "$war_file"

    touch "$LAST_COMPILE_MARKER"
    success "Deployed. App available at http://localhost:8080${CONTEXT_ROOT}"
}

cmd_undeploy() {
    require_running

    local app_name
    if ! app_name="$(find_app_name)"; then
        warn "No application is deployed."
        return 0
    fi

    info "Undeploying '${app_name}'..."
    "$ASADMIN" undeploy "$app_name"
    success "Application '${app_name}' undeployed."
}

cmd_run() {
    local start_arg="${1:-}"
    cmd_start "$start_arg"
    cmd_deploy
}

cmd_restart() {
    cmd_stop
    cmd_run "$@"
}

cmd_ui() {
    require_running
    require_deployed

    local exploded
    exploded="$(find_exploded_dir)"
    if [[ -z "$exploded" ]]; then
        error "Could not find exploded deployment directory."
        exit 1
    fi

    info "Syncing UI files and resources to exploded deployment..."
    sync_ui_files "$exploded"
    sync_resource_files "$exploded"
    success "UI and resource files synced. Refresh your browser to see changes."
}

cmd_classes() {
    local verbose=false
    if [[ "${1:-}" == "-v" || "${1:-}" == "--verbose" ]]; then
        verbose=true
    fi

    local total_start
    total_start=$(now_ms)

    require_running
    require_deployed

    local hotswap_src="$PROJECT_DIR/tools/HotSwap.java"
    local hotswap_class="$PROJECT_DIR/tools/HotSwap.class"

    # Compile HotSwap utility on first use
    if [[ ! -f "$hotswap_class" ]] || [[ "$hotswap_src" -nt "$hotswap_class" ]]; then
        info "Compiling HotSwap utility (first time)..."
        javac -d "$PROJECT_DIR/tools" "$hotswap_src"
    fi

    cd "$PROJECT_DIR"
    local timestamp changed_files needs_swap=true

    # Try incremental compile (fast path)
    if changed_files=$(find_changed_java_files); then
        local file_count
        file_count=$(( $(echo "$changed_files" | wc -l) ))

        ensure_classpath_cache
        local cached_cp
        cached_cp=$(<"$CLASSPATH_CACHE")

        # Resolve Lombok JAR dynamically from classpath cache (version-agnostic, optional)
        local lombok_jar
        lombok_jar=$(grep -oE '[^:]*lombok[^:]*\.jar' "$CLASSPATH_CACHE" | head -1)
        local processor_args=""
        if [[ -n "$lombok_jar" ]]; then
            processor_args="-processorpath $lombok_jar"
        fi

        # Detect Java version from pom.xml
        local java_version
        java_version=$(detect_java_version)
        local version_args=""
        if [[ -n "$java_version" ]]; then
            version_args="--source $java_version --target $java_version"
        else
            warn "Could not detect Java version from pom.xml (set maven.compiler.release or maven.compiler.source). Falling back to system default."
        fi

        timestamp=$(now_ms)
        info "Incremental compile: ${file_count} file(s)..."
        if [[ "$verbose" == true ]]; then
            echo "$changed_files" | while read -r f; do
                printf '%b\n' "  ${CYAN}→${NC} ${f#"$JAVA_SOURCE_DIR"/}"
            done
        fi

        local javac_rc=0
        # Compile only changed files with optional Lombok processorpath.
        # No --sourcepath: prevents javac from cascading to unchanged files.
        # target/classes on classpath: resolves references to already-compiled classes.
        # shellcheck disable=SC2086
        javac $version_args -encoding UTF-8 \
            -classpath "${cached_cp}:${CLASSES_DIR}" \
            $processor_args \
            -d "$CLASSES_DIR" \
            $changed_files 2>&1 || javac_rc=$?

        if [[ $javac_rc -ne 0 ]]; then
            warn "Incremental javac failed. Falling back to full Maven compile..."
            local fb_start
            fb_start=$(now_ms)
            "$MVNW" compile -q
            touch "$LAST_COMPILE_MARKER"
            success "Full compile $(elapsed "$fb_start")"
        else
            touch "$LAST_COMPILE_MARKER"
            success "Compiled ${file_count} file(s) $(elapsed "$timestamp")"
        fi
    elif [[ ! -f "$LAST_COMPILE_MARKER" ]]; then
        # First run — need full compile to establish baseline
        timestamp=$(now_ms)
        info "First run — full Maven compile to establish baseline..."
        "$MVNW" compile -q
        touch "$LAST_COMPILE_MARKER"
        success "Baseline compile $(elapsed "$timestamp")"
        info "Baseline only — skipping hot-swap (deployed app already has these classes)."
        info "Total: $(elapsed "$total_start")"
        return 0
    else
        needs_swap=false
        success "No changed .java files. Nothing to do."
        info "Total: $(elapsed "$total_start")"
        return 0
    fi

    # Hot-swap via JDWP
    local swap_start swap_rc=0
    swap_start=$(now_ms)
    info "Hot-swapping classes via JDWP (port ${DEBUG_PORT})..."
    local verbose_flag=""
    if [[ "$verbose" == true ]]; then verbose_flag="-v"; fi
    java -cp "$PROJECT_DIR/tools" HotSwap "$DEBUG_PORT" "$CLASSES_DIR" "${timestamp:-0}" $verbose_flag || swap_rc=$?

    if [[ $swap_rc -ne 0 ]]; then
        warn "JDWP hot swap failed (structural change?). Falling back to full redeploy..."
        local fb_start
        fb_start=$(now_ms)
        "$MVNW" package -DskipTests -q
        local fb_war fb_app
        fb_war="$(find_war_file)"
        if fb_app="$(find_app_name)"; then
            "$ASADMIN" undeploy "$fb_app" 2>/dev/null || true
        fi
        "$ASADMIN" deploy --contextroot "$CONTEXT_ROOT" "$fb_war"

        success "Redeployed via fallback $(elapsed "$fb_start"). App at http://localhost:8080${CONTEXT_ROOT}"
    else
        success "Hot-swap done $(elapsed "$swap_start")"
    fi

    info "Total: $(elapsed "$total_start")"
}

cmd_full() {
    require_running

    info "Full rebuild + redeploy..."
    cd "$PROJECT_DIR"
    "$MVNW" clean package -DskipTests -q
    local war_file
    war_file="$(find_war_file)"
    success "WAR built."

    # Undeploy first for cleaner classloader release
    local app_name
    if app_name="$(find_app_name)"; then
        info "Undeploying '${app_name}'..."
        "$ASADMIN" undeploy "$app_name" 2>/dev/null || true
    fi

    info "Deploying..."
    "$ASADMIN" deploy --contextroot "$CONTEXT_ROOT" "$war_file"

    touch "$LAST_COMPILE_MARKER"
    success "Deployed. App available at http://localhost:8080${CONTEXT_ROOT}"
}

cmd_sync() {
    cmd_ui
    cmd_classes "$@"
}

cmd_log() {
    if [[ ! -f "$LOG_FILE" ]]; then
        error "Log file not found: ${LOG_FILE}"
        echo "  Is the domain running? Try: $0 start"
        exit 1
    fi

    if [[ "${1:-}" == "--err" ]]; then
        info "Tailing server log (errors only)... ${YELLOW}Ctrl+C to stop${NC}"
        tail -f "$LOG_FILE" | grep --line-buffered -E 'SEVERE|ERROR|Exception|Caused by'
    else
        info "Tailing server log... ${YELLOW}Ctrl+C to stop${NC}"
        tail -f "$LOG_FILE"
    fi
}

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
${BOLD}gf${NC} — GlassFish dev workflow CLI

${BOLD}Usage:${NC}  ./gf <command> [options]

${BOLD}Quick start:${NC}
  ${CYAN}1.${NC} ./gf run                       ${YELLOW}# start server + build + deploy${NC}
  ${CYAN}2.${NC} ./gf sync -v                   ${YELLOW}# after code changes${NC}

${BOLD}Server:${NC}
  ${GREEN}start${NC} [--no-debug]    Start domain (debug on port ${DEBUG_PORT} by default)
  ${GREEN}stop${NC}                  Stop the domain
  ${GREEN}run${NC} [--no-debug]      Start + build + deploy (zero to running)
  ${GREEN}restart${NC} [--no-debug]  Stop + start + build + deploy

${BOLD}Development:${NC}
  ${GREEN}ui${NC}                    Sync UI files + .jrxml reports to deployment
  ${GREEN}classes${NC} [-v]           Incremental compile + JDWP hot-swap (~3-6s)
  ${GREEN}sync${NC} [-v]              UI sync + classes hot-swap in one command
  ${GREEN}full${NC}                  Clean WAR build + asadmin redeploy (~30-60s)
  ${GREEN}deploy${NC}                Build WAR + deploy (fresh deployment)
  ${GREEN}undeploy${NC}              Remove the deployed application

${BOLD}Diagnostics:${NC}
  ${GREEN}log${NC} [--err]           Tail server log (--err filters errors only)

${BOLD}Examples:${NC}
  ./gf run                 # First time: start server + build + deploy
  ./gf sync -v             # Most common: sync UI + hot-swap Java classes
  ./gf ui                  # Quick-sync after editing XHTML/CSS/JS or .jrxml
  ./gf classes             # Recompile + hot-reload Java (no UI sync)
  ./gf log --err           # Watch only error lines in server log
  ./gf full                # Structural change? Full rebuild + redeploy

See ${CYAN}README.md${NC} for setup and architecture details.
EOF
}

# ─── Main ─────────────────────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

COMMAND="$1"
shift

case "$COMMAND" in
    -h|--help|help) usage ;;
    start)    cmd_start "$@" ;;
    stop)     cmd_stop ;;
    deploy)   cmd_deploy ;;
    undeploy) cmd_undeploy ;;
    run)      cmd_run "$@" ;;
    restart)  cmd_restart "$@" ;;
    ui)       cmd_ui ;;
    classes)  cmd_classes "$@" ;;
    sync)     cmd_sync "$@" ;;
    full)     cmd_full ;;
    log)      cmd_log "$@" ;;
    *)
        error "Unknown command: ${COMMAND}"
        echo ""
        usage
        exit 1
        ;;
esac
