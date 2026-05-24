# gf — GlassFish Dev Workflow CLI

> **Stop waiting 60 seconds for GlassFish to redeploy.** `gf` hot-swaps your Java code in 3–6 seconds, reloads JasperReports templates without a restart, and works from any terminal.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![CI](https://github.com/riyadomf/glassfish-hotswap-cli/actions/workflows/ci.yml/badge.svg)](https://github.com/riyadomf/glassfish-hotswap-cli/actions/workflows/ci.yml)
[![GlassFish 7 & 8](https://img.shields.io/badge/GlassFish-7%20%7C%208-blue)](https://glassfish.org/)
[![Java 17+](https://img.shields.io/badge/Java-17%2B-orange)](https://adoptium.net/)

## Demo

<!--
  To record the demo GIF:
    1. Install vhs (https://github.com/charmbracelet/vhs)
    2. From this repo root, against a deployed Jakarta EE project: vhs docs/demo.tape
    3. Commit the produced docs/demo.gif and uncomment the image line below.
-->
<!-- ![gf in action](docs/demo.gif) -->

```text
$ ./gf sync -v
→ Incremental compile (2 files changed)... done in 1.4s
→ JDWP hot-swap (com.example.HelloController)... done in 0.9s
✓ Live in 3.1s. No restart, no redeploy.
```

*Edit a Java file, run `gf sync`, see the change live in the running server.*

## Why use `gf`?

If you've worked on a Jakarta EE app, you know the cycle: change one line, save, wait 30–60 seconds while GlassFish redeploys, lose your train of thought. Do that twenty times a day and you've spent an hour staring at a deploy log.

`gf` gets that wait down to **3–6 seconds** by using JDWP — the JVM's built-in debugger protocol — to hot-swap the modified classes directly into the running server. When a change is too structural for hot-swap (new method signatures, new fields), it falls back to a normal redeploy automatically. You never have to think about which mode to use.

**What you get:**

- **Fast feedback loop.** 3–6 second hot-swap vs 30–60 second redeploy. The single biggest quality-of-life upgrade for GlassFish development.
- **JasperReports template hot-reload.** Edit a `.jrxml` file, run `./gf ui`, and the new template is live on the next report generation. IntelliJ's GlassFish plugin doesn't do this.
- **Works from any terminal.** VS Code, Vim, IntelliJ Community, plain SSH — anywhere you can run a shell. No IDE lock-in, no IntelliJ Ultimate license required.
- **Automatic fallback.** Hot-swap when it works, full redeploy when it doesn't. The tool figures out which one you need.
- **Claude Code integration.** Comes with a `/gf` skill so Claude Code knows the whole workflow out of the box.

## How is this different from IntelliJ's GlassFish plugin?

| | `gf` | IntelliJ GlassFish plugin |
|---|---|---|
| JasperReports `.jrxml` hot-reload | ✅ | ❌ |
| Incremental Java compile (only changed files) | ✅ | ❌ (full project build) |
| Automatic fallback to full redeploy | ✅ | ❌ |
| Works outside IntelliJ | ✅ (any terminal) | ❌ (IntelliJ only) |
| Claude Code integration | ✅ | ❌ |
| Requires IntelliJ Ultimate (paid) | ❌ | ✅ |
| Cost | Free (MIT) | Bundled with Ultimate |

## Installation

**Option 1: Copy into your project**

```bash
# From your Maven + GlassFish project root:
curl -fsSL https://raw.githubusercontent.com/riyadomf/glassfish-hotswap-cli/main/gf -o gf
mkdir -p tools
curl -fsSL https://raw.githubusercontent.com/riyadomf/glassfish-hotswap-cli/main/tools/HotSwap.java -o tools/HotSwap.java
chmod +x gf

# Optional: resource setup script (JDBC, JMS, JNDI config)
curl -fsSL https://raw.githubusercontent.com/riyadomf/glassfish-hotswap-cli/main/setup-glassfish-resources.sh -o setup-glassfish-resources.sh
curl -fsSL https://raw.githubusercontent.com/riyadomf/glassfish-hotswap-cli/main/db.properties.sample -o db.properties.sample
curl -fsSL https://raw.githubusercontent.com/riyadomf/glassfish-hotswap-cli/main/env.properties.sample -o env.properties.sample
chmod +x setup-glassfish-resources.sh
```

**Option 2: Clone and copy**

```bash
git clone https://github.com/riyadomf/glassfish-hotswap-cli.git
cp glassfish-hotswap-cli/gf /path/to/your/project/
cp -r glassfish-hotswap-cli/tools /path/to/your/project/
```

Add these to your project's `.gitignore`:

```gitignore
tools/*.class
tools/.classpath.cache
```

## Prerequisites

- **JDK 17+** (project compiles with `--source`/`--target` auto-detected from pom.xml)
- **GlassFish 7 or 8** installed locally
- **Maven** (`./mvnw` wrapper or `mvn` on PATH — auto-detected)
- **rsync** (pre-installed on Linux and macOS)

## Setup

```bash
# 1. Add GlassFish bin/ to your shell profile:
#    Linux  (~/.bashrc):   export PATH="/path/to/glassfish8/bin:$PATH"
#    macOS  (~/.zshrc):    export PATH="/path/to/glassfish8/bin:$PATH"

# 2. Start server + build + deploy
./gf run

# 3. After code changes, sync + hot-swap
./gf sync -v
```

## Configuration

The script uses sensible defaults. Override via environment variables if needed:

| Variable | Default | Description |
|---|---|---|
| `GF_DOMAIN` | `domain1` | GlassFish domain name |
| `GF_CONTEXT_ROOT` | `/` | Deployment context root |
| `GF_DEBUG_PORT` | `9009` | JDWP debug port |
| `GF_JNDI_PREFIX` | `app` | JNDI namespace prefix for custom resources (must match `setup-glassfish-resources.sh`) |

The WAR file is auto-detected from `target/*.war` after each build. The Java version for incremental compilation is auto-detected from `<maven.compiler.release>` or `<maven.compiler.source>` in your `pom.xml`.

## Daily Workflow

```
./gf run              ← once per session (starts GlassFish + deploys)
  ↓
./gf sync -v          ← repeat after each code change
  ↓                      (syncs UI files + compiles + JDWP hot-swap)
./gf log --err        ← in a separate terminal (tail error logs)
```

- **UI-only changes** (XHTML/CSS/JS): `./gf ui` — instant rsync, just refresh browser
- **Report templates** (.jrxml): `./gf ui` — rsync to exploded deployment, refresh on next report generation
- **Java changes**: `./gf classes -v` — incremental compile + hot-swap (~3-6s)
- **Both**: `./gf sync -v` — does both in one command (most common)
- **Structural changes** (new fields, method signatures): `./gf full` — full WAR rebuild + redeploy (~30-60s)

## Commands

### Server Lifecycle
| Command | Description |
|---|---|
| `./gf start [--no-debug]` | Start domain (debug on port 9009 by default) |
| `./gf stop` | Stop the domain |
| `./gf setup [--delete]` | Configure JDBC/JMS/JNDI resources (auto-detects `db.properties` + `env.properties`) |
| `./gf run [--no-debug]` | Start + build WAR + deploy (zero to running) |
| `./gf restart [--no-debug]` | Stop + start + build + deploy |

### Development
| Command | Description |
|---|---|
| `./gf ui` | Sync UI files + .jrxml reports to exploded deployment |
| `./gf classes [-v]` | Incremental compile + JDWP hot-swap (~3-6s) |
| `./gf sync [-v]` | UI sync + classes hot-swap (most common) |
| `./gf full` | Clean WAR build + asadmin redeploy (~30-60s) |
| `./gf deploy` | Build WAR + fresh deploy |
| `./gf undeploy` | Remove the deployed application |

### Diagnostics
| Command | Description |
|---|---|
| `./gf log [--err]` | Tail server log (--err filters errors only) |

## How It Works

### Incremental Compile + Hot-Swap

1. `find` detects `.java` files modified since the last successful compile
2. `javac` compiles only those files (with Lombok annotation processing, if Lombok is on the classpath)
3. `HotSwap.java` connects to the running JVM via JDWP (port 9009) and redefines the changed classes in-place
4. If an IDE debugger is already attached (port occupied), skips redeploy and prompts to hot-swap from the IDE
5. If hot-swap fails (structural change), falls back to full Maven build + asadmin redeploy

### File Sync

`rsync` copies XHTML, CSS, JS, and image files from `src/main/webapp/` into GlassFish's exploded deployment directory, and `.jrxml` report templates from `src/main/resources/reports/` into `WEB-INF/classes/reports/`. Changes are visible on browser refresh (UI) or next report generation (.jrxml) without redeployment.

## Files

```
gf                              ← main CLI script (project root)
setup-glassfish-resources.sh    ← JDBC/JMS/JNDI resource setup (optional)
db.properties.sample            ← sample database config
env.properties.sample           ← sample application config
tools/
  HotSwap.java                  ← JDWP hot-swap utility (tracked)
  HotSwap.class                  ← compiled on first use (gitignored)
  .classpath.cache               ← Maven dependency cache (gitignored)
```

## Debugging with IntelliJ IDEA

`./gf start` launches GlassFish with JDWP debug enabled on port **9009**. To attach IntelliJ IDEA:

1. **Run → Edit Configurations → + → Remote JVM Debug**
2. Set **Port** to `9009`, leave other defaults (Attach, Socket, localhost)
3. Click **Debug** — IntelliJ connects to the running GlassFish instance

You can now set breakpoints, inspect variables, and step through code.

> **Note:** JDWP only allows one debugger connection at a time. When IntelliJ is attached, `./gf classes` will compile your changes but skip the JDWP hot-swap step — use IntelliJ's **Run → Reload Changed Classes** (Ctrl+F10) instead. Disconnect IntelliJ's debugger to let `./gf classes` handle hot-swap directly.

## Claude Code Integration

The `/gf` skill lets you run `./gf` commands directly from within Claude Code:

```
/gf sync -v       ← syncs UI + hot-swaps Java changes
/gf full           ← full WAR rebuild + redeploy
/gf log --err      ← tail error logs
/gf                ← shows command quick reference
```

Any arguments after `/gf` are passed straight to the `./gf` script. With no arguments, it prints a quick reference of all available commands. Copy the `.claude/skills/gf/` directory into your project to enable the skill.

## Resource Setup (Optional)

The `setup-glassfish-resources.sh` script creates JDBC connection pools, JNDI custom resources, and optionally JMS resources in GlassFish. It's idempotent — safe to run multiple times without "already exists" errors.

```bash
# 1. Configure the script: edit variables at the top of setup-glassfish-resources.sh
#    (JDBC pool name, datasource name, JNDI prefix, driver class, etc.)

# 2. Create your properties files from the samples:
cp db.properties.sample db.properties
cp env.properties.sample env.properties
# Edit both files with your actual values, then secure them:
chmod 600 db.properties env.properties

# 3. Run the setup (GlassFish must be running) — either way works:
./gf setup                                                  # via the gf CLI
./setup-glassfish-resources.sh db.properties env.properties # directly

# To tear down and recreate all resources:
./gf setup --delete
```

Each key in `env.properties` becomes a JNDI custom resource under the configured prefix (default: `app/`). Look them up in your application with `@Resource(lookup = "app/your.key")`.

### Auto-sync on deploy

`./gf deploy` and `./gf full` automatically check `env.properties` and create any missing JNDI custom resources before deploying. So adding a new key to `env.properties` and running `./gf full` is enough — no need to re-run `setup` manually. (Updates to existing values still require `./gf setup --delete` to recreate.)

If `env.properties` doesn't exist, the auto-sync silently skips (so projects without JNDI custom resources are unaffected).

## Troubleshooting

**"asadmin not found on PATH"** — Add GlassFish's `bin/` directory to your shell PATH (e.g., `export PATH="/path/to/glassfish8/bin:$PATH"` in `~/.bashrc` or `~/.zshrc`).

**JDWP hot-swap fails** — The JVM can't redefine classes with structural changes (new/removed fields or methods). Use `./gf full` for a clean redeploy.

**XHTML changes not visible** — Mojarra 4.1.6+ sets `FACELETS_REFRESH_PERIOD=-1` when `PROJECT_STAGE=Production`. Ensure your JSF project stage is set to `Development` (e.g., via a context parameter in `web.xml` or a Maven profile). If pages are still stale, try `./gf full`.

**Debug port not reachable** — Either an IDE debugger is already attached (JDWP allows only one connection), or GlassFish wasn't started in debug mode. If an IDE debugger is connected, `./gf classes` will compile and prompt you to hot-swap from the IDE. Otherwise, restart with `./gf start` (debug is on by default).

**Classpath cache stale** — If you changed `pom.xml` dependencies, the cache auto-refreshes on next `./gf classes`. To force: delete `tools/.classpath.cache`.

## License

[MIT](LICENSE)
