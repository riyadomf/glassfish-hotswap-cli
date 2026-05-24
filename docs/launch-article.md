# How I Reduced GlassFish Redeploy Time from 2 Minutes to 5 Seconds

*Or: how I built a CLI-based hot-swap agent that doesn't need IntelliJ Ultimate, doesn't need a custom JVM, and reloads JasperReports templates while it's at it.*

*Originally posted at: TODO add Dev.to URL once published.*
*Repo: [github.com/riyadomf/glassfish-hotswap-cli](https://github.com/riyadomf/glassfish-hotswap-cli)*

---

## The 2-minute cliff

If you've worked on a Jakarta EE app on GlassFish, you know the rhythm:

1. Change one line of Java.
2. Save.
3. Wait. Maven builds the WAR. GlassFish undeploys the old version, deploys the new one, re-warms the JPA cache, re-initializes EJBs and CDI beans, restarts the JSF lifecycle, finally finishes.
4. By the time the deploy log scrolls past, you've forgotten what you were doing.

On a recent enterprise project I clocked it — a clean redeploy averaged **around two minutes** once the app was big enough to have non-trivial startup. I do this maybe forty times a day. That's a working hour or more, every day, staring at a deploy log.

The really frustrating part: **most of those changes don't need a redeploy at all.** Tweaking a method body, fixing a logic bug, changing a return value — the JVM is perfectly capable of swapping a single class without restarting anything. The infrastructure for it has shipped with every JVM since Java 5. The problem is that nobody had wired that capability into a workflow I could actually use from my editor without paying a license fee or swapping out my JVM.

So I built one. It's called `gf`, it's a single Bash script plus 200 lines of Java, and it gets that 2-minute wait down to **3 to 6 seconds.** Five seconds is the rough mental shorthand I now use.

It's at [github.com/riyadomf/glassfish-hotswap-cli](https://github.com/riyadomf/glassfish-hotswap-cli), MIT-licensed.

## What I tried first

Before writing my own tool, I went through every option I could find.

**IntelliJ's GlassFish plugin.** It does class hot-swap on debug, but only inside IntelliJ Ultimate — which is paid. Even if your team has Ultimate licenses, you're locked into IntelliJ for the fast-feedback workflow. I bounce between VS Code (for typing speed), Vim (over SSH), and IntelliJ Community for refactors. I didn't want my dev loop to be the deciding factor for which editor I'm allowed to open.

**JRebel.** Genuinely excellent. Costs €600/year per developer. A hard sell at any company that hasn't already standardized on it, and a non-starter for side projects or junior teammates.

**Plain `asadmin redeploy`.** No improvement over what I already had — a full WAR redeploy is the slow path we're trying to avoid.

**HotSwapAgent.** Promising in theory, fiddly in practice. It wants specific JVM configuration that didn't compose cleanly with our team's existing GlassFish setup, and the docs assume you already know how its plugin system works.

**DCEVM (with or without HotSwapAgent).** This is the heavyweight option. DCEVM is a HotSpot patch that lets you redefine class *structure* — add methods, change signatures, even rename fields. Stack HotSwapAgent on top and you get framework-aware reload (Spring beans get re-wired, Hibernate caches get cleared, the works). It's genuinely powerful when it works. But:

- It requires running on a **custom JVM build**. Not a flag on a stock JDK, not an agent jar — an actual replacement `java` binary.
- DCEVM's release cadence has historically **lagged mainline JDK LTSes by a year or more**. If your project is pinned to a newer JDK, you may not have a DCEVM build available at all.
- On enterprise setups where the JVM choice is decided three layers above me on the org chart, swapping it out isn't an option.

What I actually wanted was something that ran on **whatever JDK my team already had**, integrated with **whatever editor I felt like using that day**, and just did the obvious thing: recompile the file I touched, push the bytes into the running server, and get out of the way.

Nothing existed that did all three.

## A 60-second tour

Here's what `gf` looks like in practice:

```
$ ./gf sync -v
▶ Incremental compile: 2 file(s)...
✔ Compiled 2 file(s) (1.4s)
▶ Hot-swapping classes via JDWP (port 9009)...
✔ Hot-swapped 2 class(es). (0.9s)
✔ UI and resource files synced. Refresh your browser.
✔ Total (3.1s)
```

That's the entire dev loop. Edit a file. Run `./gf sync`. The change is live in the running server. No restart, no redeploy, no waiting.

A few sibling commands round out the workflow:

- `./gf ui` — rsync XHTML, CSS, JS, and JasperReports templates into the exploded deployment. No compile, no JVM round-trip. Just refresh the browser.
- `./gf classes -v` — compile + hot-swap only (no UI sync). What you want when you're iterating purely on Java code.
- `./gf full` — clean Maven build + full `asadmin` redeploy. The escape hatch when you've changed something hot-swap can't handle.
- `./gf log --err` — tail the GlassFish server log, filtered to errors. Run it in a second pane.

The whole thing is a single Bash script plus one Java file you can drop into any Maven + GlassFish 7/8 project. It's been my daily driver for the past several months.

## Why not just buy IntelliJ Ultimate?

The honest answer is: I tried, and it still wasn't enough.

**JasperReports templates.** This was the killer. Half the enterprise GlassFish apps I've worked on use JasperReports for PDF generation. The `.jrxml` template files live in `src/main/resources/reports/` and get compiled at runtime by `JasperCompileManager`. IntelliJ's "Update resources" action — the thing that's supposed to push your changes into a running server without redeploying — **only knows about webapp files**: XHTML, CSS, JS, images. It doesn't touch `.jrxml`.

So even with Ultimate, my workflow for a report-template change was: edit the `.jrxml`, redeploy (2 minutes), check the PDF. Or copy the file by hand into GlassFish's exploded deployment directory and hope I got the path right.

`./gf ui` runs an `rsync` from `src/main/resources/reports/` into `WEB-INF/classes/reports/` of the running deployment. Next time the user generates a report, JasperReports picks up the new template. No restart. Cycle drops from 2 minutes to under a second. **This alone saves me hours every week.**

**The classloader churn problem.** Every time you redeploy a GlassFish app, the server spins up a new application classloader. The old one — and every class it ever loaded — can't be garbage collected until every reference to it is gone. In long-running development sessions with dozens of redeploys, this is famously how you end up with `OutOfMemoryError: Metaspace` and a domain you have to restart.

JDWP hot-swap **reuses the existing classloader**. The class object in memory is updated in place, no new classloader is created, no leak accumulates. On a typical dev day I'll hot-swap forty or fifty times and never touch a redeploy. The domain stays healthy for the full session.

**No IDE lock-in.** I bounce editors. I want the fast feedback to follow me, not be hostage to whichever editor's window is in focus. `gf` runs from any terminal — VS Code's integrated terminal, a Vim split, a plain SSH session, the Claude Code shell. It doesn't know or care what's editing the source files.

**No IntelliJ Ultimate required.** For me, this means I can use IntelliJ Community when I want a refactor and VS Code when I want to type. For teams, it means juniors and contractors on Community licenses get the same fast loop as the seniors on Ultimate. The tool is MIT-licensed, no per-seat cost, no expiring trial.

## How JDWP hot-swap actually works

JDWP — the Java Debug Wire Protocol — is the JVM's built-in debugger interface. Start a JVM with `-agentlib:jdwp=transport=dt_socket,server=y,address=*:9009` and it opens a socket waiting for debugger commands. That's what IntelliJ talks to when you set a breakpoint.

The interesting thing about JDWP, and the part most people don't think about, is that the protocol supports **redefining a class's bytecode in a running JVM**. You connect, you hand it the new bytes for `com.example.HelloController`, and the JVM atomically replaces the existing class definition. Existing instances keep their identity and field values. Method bodies match by signature and get the new implementation immediately.

The Java side of that conversation is the JDI — the Java Debug Interface — which lives in the `jdk.jdi` module. The core of `gf`'s hot-swap client is about ten lines:

```java
VirtualMachine vm = connector.attach(arguments);   // talk to the JVM

for (Path classFile : changedClassFiles) {
    String className = classFile.toClassName();
    List<ReferenceType> types = vm.classesByName(className);
    if (types.isEmpty()) continue;                  // class not loaded yet, skip

    byte[] bytecode = Files.readAllBytes(classFile);
    vm.redefineClasses(Map.of(types.get(0), bytecode));
}

vm.dispose();
```

The Bash side does the orchestration: figure out which `.java` files changed since the last successful build (a `find` against a marker file), run `javac` on just those (with the Lombok processor auto-detected from the classpath), then hand the resulting `.class` files to the Java JDI client.

## The interesting bit: when hot-swap can't help

JDWP's `redefineClasses` has one limitation. It can change method **bodies**, but it can't change the **shape** of a class. Add a new field, add a new method, change a method signature — the JVM rejects the swap with `UnsupportedOperationException: add method not implemented`.

(There's a JVM flag, `-XX:+AllowRedefinitionToAddDeleteMethods`, that loosens this. It's still not enough for arbitrary refactors, and has compatibility gotchas with annotation processors and synthetic methods. I decided not to rely on it.)

So `gf` needs a decision tree: try the hot-swap, fall back to a full redeploy if it fails. But there are actually four cases:

1. **Hot-swap works** → 3–6 second happy path. Done.
2. **Hot-swap fails with "structural change"** → fall back to `mvn clean package` + `asadmin redeploy`. Slow (~45–120s) but correct.
3. **Can't connect to the JDWP port at all** → either GlassFish isn't in debug mode, or an IDE debugger is already attached holding the port. These need different responses.
4. **JVM doesn't support `canRedefineClasses`** → something's wrong with the debug-options config. Print a diagnostic and bail.

Distinguishing case 2 from case 3 turned out to matter a lot. If I always fell back to a full redeploy when JDWP failed, then attaching IntelliJ's debugger — which holds the port — would trigger an unwanted 2-minute redeploy every time I ran `gf sync`. That defeats the entire point.

The fix was simple but only obvious in hindsight: use different exit codes from the Java client. `exit 1` for structural change, `exit 2` for connection failure. The Bash script reads the exit code and branches:

```bash
java -cp tools HotSwap "$DEBUG_PORT" target/classes "$SINCE" $VERBOSE_FLAG
case $? in
    0) ;;  # success
    1) full_redeploy ;;                                          # structural change
    2) warn "IDE debugger attached — use IDE hot-swap instead" ;; # port held
esac
```

Tiny detail. Huge quality-of-life difference.

## The things IntelliJ won't do (and why I needed them)

Beyond hot-swap itself, there were three more friction points the tool ended up smoothing over. They sound small individually; together they're the difference between "neat experiment" and "I run this all day."

**Auto-create JNDI resources on deploy.** Every time someone on the team added a new config key to `env.properties`, you had to remember to create a matching JNDI custom resource in GlassFish, or the next deploy would fail with `NamingException` mid-startup. `./gf deploy` and `./gf full` now read `env.properties` and create any missing resources before pushing the WAR. Adding a config value is just adding a line; nobody needs to remember the `asadmin create-custom-resource` incantation.

**Self-healing `domain.xml` debug-options.** GlassFish's `domain.xml` occasionally ends up with the wrong JDWP flags (`server=n` instead of `y`, or `suspend=y` instead of `n`) after certain admin operations. The result is a domain that starts but doesn't accept debugger connections — which silently breaks hot-swap until you go spelunking through the XML. `./gf start` now detects the broken pattern and rewrites it before launch.

**Useful error messages when `asadmin` can't authenticate.** If you haven't run `asadmin login`, the first command that touches the admin endpoint dies with `Authentication failed for user: null` and the script exits half-way through whatever you were doing. The latest version probes auth up front and prints the two recovery commands (`asadmin login` and `asadmin change-admin-password`) explicitly.

## A note on the Claude Code integration

The repo ships with a [Claude Code](https://www.anthropic.com/news/claude-code) skill in `.claude/skills/gf/`. If you use Claude Code as part of your workflow, the `/gf` slash command lets Claude run any `gf` subcommand directly — `/gf sync -v`, `/gf log --err`, `/gf full`. With no arguments, Claude gets a quick reference of the whole CLI.

This wasn't a planned feature; I added it because I kept asking Claude "can you redeploy that and tail the log" and realized the skill should just *be* the workflow rather than me re-explaining it every session.

## What I learned

A few things that surprised me along the way.

**Bash robustness is mostly about defaults.** `set -euo pipefail` at the top of every script catches an absurd number of bugs that would otherwise silently swallow errors. `rsync` errors in particular love to slip past `set -e` because they exit non-zero on the most boring conditions (e.g. an optional directory not existing). I ended up wrapping `rsync` calls with explicit error-to-warning handling instead of letting them kill the script.

**Idempotency is worth the effort.** The companion `setup-glassfish-resources.sh` script creates JDBC pools, JMS queues, and JNDI resources from a properties file. The first version was a 100-line wall of `asadmin create-*` commands. If you ran it twice you got "resource already exists" errors and the script aborted half-way through, leaving GlassFish in an inconsistent state. Rewriting it to check-then-create was annoying but it's the difference between a tool people actually use and a tool they're afraid of.

**Auto-detection beats configuration.** I started with environment variables for everything: Java version, Maven wrapper path, Lombok presence, GlassFish domain name. Then I realized every single one is derivable from the project itself. The `pom.xml` tells you the Java version. The presence of `mvnw` tells you which Maven to use. A Lombok dependency on the classpath tells you whether to enable annotation processing. By the end the only required setup was "put GlassFish on your PATH." Everything else just works.

**Exit codes carry information.** The distinction between "hot-swap failed because the change is too big" and "hot-swap failed because we can't even connect" is invisible from a thrown exception in the parent script, but trivial from an exit code. The fact that I shipped the first version with a single exit code for both was the biggest single source of confused-user friction. Don't lump categorically different failures into one signal.

## Try it

If you work on Jakarta EE apps with GlassFish 7 or 8, give `gf` a try:

```bash
# Drop into any Maven + GlassFish project root:
curl -fsSL https://raw.githubusercontent.com/riyadomf/glassfish-hotswap-cli/main/gf -o gf
mkdir -p tools
curl -fsSL https://raw.githubusercontent.com/riyadomf/glassfish-hotswap-cli/main/tools/HotSwap.java -o tools/HotSwap.java
chmod +x gf
./gf run
```

The full README walks through the rest of the setup. The tool is MIT-licensed, runs on Linux and macOS, supports JDK 17 / 21 / 25, and works out of the box on any Maven + GlassFish 7 or 8 project.

If you find it useful, a ⭐ on the repo means a lot — it helps the project show up for the next person looking for the same thing.

If something doesn't work, open an issue. I'm watching.

🔗 [github.com/riyadomf/glassfish-hotswap-cli](https://github.com/riyadomf/glassfish-hotswap-cli)
