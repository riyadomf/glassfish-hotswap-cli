---
name: gf
description: GlassFish dev workflow CLI tool
disable-model-invocation: true
argument-hint: [command] [options]
allowed-tools: Bash(./gf *)
---

# Execution

Run the GlassFish dev workflow command:

```bash
./gf $ARGUMENTS
```

If no arguments were provided, show the quick reference below instead of running a command.

---

# Command Reference

## Commands

### Server Lifecycle
| Command | Description |
|---|---|
| `./gf start [--no-debug]` | Start domain (debug on port 9009 by default) |
| `./gf stop` | Stop the domain |
| `./gf setup [--delete]` | Configure JDBC/JMS/JNDI resources from db.properties + env.properties |
| `./gf run [--no-debug]` | Start + build WAR + deploy (zero to running) |
| `./gf restart [--no-debug]` | Stop + start + build + deploy |

### Development
| Command | Description |
|---|---|
| `./gf ui` | rsync XHTML/CSS/JS/images + .jrxml reports to exploded deployment |
| `./gf classes [-v]` | Incremental javac + JDWP hot-swap (~3-6s) |
| `./gf sync [-v]` | UI sync + classes hot-swap (most common) |
| `./gf full` | Clean WAR build + asadmin redeploy (~30-60s) |
| `./gf deploy` | Build WAR + fresh deploy |
| `./gf undeploy` | Remove the deployed application |

### Diagnostics
| Command | Description |
|---|---|
| `./gf log [--err]` | Tail server log (--err filters errors only) |

## When to Use Which Command

- **Changed XHTML/CSS/JS only** → `./gf ui`
- **Changed .jrxml report templates** → `./gf ui`
- **Changed Java code (method bodies)** → `./gf classes -v`
- **Changed both** → `./gf sync -v`
- **Structural Java changes (new fields/methods, entity changes)** → `./gf full`
- **First time or clean state** → `./gf run`

## Architecture

```
./gf sync -v
  │
  ├─ UI + resource sync (rsync)
  │    src/main/webapp/           ──rsync──► GF exploded deployment dir
  │    src/main/resources/reports/ ──rsync──► WEB-INF/classes/reports/
  │
  └─ Classes hot-swap
       1. find -newer → changed .java files
       2. javac (incremental, Lombok processorpath)
       3. HotSwap.java → JDWP redefineClasses on port 9009
       4. If IDE debugger attached → compile only, skip redeploy
       5. If structural change → fallback: mvnw package + asadmin redeploy
```

## Key Files

| File | Purpose |
|---|---|
| `gf` | Main CLI script (project root) |
| `tools/HotSwap.java` | JDWP client that redefines classes in running GlassFish |
| `tools/.classpath.cache` | Cached Maven classpath for incremental javac (gitignored) |
