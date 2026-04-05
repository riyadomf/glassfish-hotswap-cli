# gf — GlassFish Dev Workflow CLI

A CLI tool for local GlassFish development. Handles server lifecycle, incremental Java compilation with JDWP hot-swap, and UI file syncing — all in one command.

## Why `gf` over IntelliJ's GlassFish Plugin

- **Claude Code integration** — Claude Code can use `./gf` commands autonomously, or invoke the `/gf` skill to manage the server from within the conversation
- **Hot-reload for Jasper reports** (.jrxml) — `./gf ui` syncs JasperReports templates to the running server; IntelliJ's "Update resources" only covers webapp files (XHTML/CSS/JS)
- **Incremental compile** — only recompiles changed `.java` files (~3-6s), vs IntelliJ's full project build
- **Automatic fallback** — if JDWP hot-swap fails (structural change), auto-falls back to a full redeploy. If an IDE debugger is already attached, skips the redeploy and prompts you to hot-swap from the IDE
- **Self-healing** — auto-fixes broken JDWP debug-options in `domain.xml` before startup
- **IDE-independent** — works from any terminal (VS Code, Vim, SSH), not tied to IntelliJ

## Installation

**Option 1: Copy into your project**

```bash
# From your Maven + GlassFish project root:
curl -fsSL https://raw.githubusercontent.com/riyadomf/glassfish-hotswap-cli/main/gf -o gf
mkdir -p tools
curl -fsSL https://raw.githubusercontent.com/riyadomf/glassfish-hotswap-cli/main/tools/HotSwap.java -o tools/HotSwap.java
chmod +x gf
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
gf                      ← main CLI script (project root)
tools/
  HotSwap.java          ← JDWP hot-swap utility (tracked)
  HotSwap.class          ← compiled on first use (gitignored)
  .classpath.cache       ← Maven dependency cache (gitignored)
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

## Troubleshooting

**"asadmin not found on PATH"** — Add GlassFish's `bin/` directory to your shell PATH (e.g., `export PATH="/path/to/glassfish8/bin:$PATH"` in `~/.bashrc` or `~/.zshrc`).

**JDWP hot-swap fails** — The JVM can't redefine classes with structural changes (new/removed fields or methods). Use `./gf full` for a clean redeploy.

**XHTML changes not visible** — Mojarra 4.1.6+ sets `FACELETS_REFRESH_PERIOD=-1` when `PROJECT_STAGE=Production`. Ensure your JSF project stage is set to `Development` (e.g., via a context parameter in `web.xml` or a Maven profile). If pages are still stale, try `./gf full`.

**Debug port not reachable** — Either an IDE debugger is already attached (JDWP allows only one connection), or GlassFish wasn't started in debug mode. If an IDE debugger is connected, `./gf classes` will compile and prompt you to hot-swap from the IDE. Otherwise, restart with `./gf start` (debug is on by default).

**Classpath cache stale** — If you changed `pom.xml` dependencies, the cache auto-refreshes on next `./gf classes`. To force: delete `tools/.classpath.cache`.

## License

[MIT](LICENSE)
