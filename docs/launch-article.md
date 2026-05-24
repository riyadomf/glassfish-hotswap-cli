# I cut GlassFish redeploy times from 60 seconds to 3 seconds. Here's how.

*Originally posted at: TODO add Dev.to URL once published.*
*Repo: [github.com/riyadomf/glassfish-hotswap-cli](https://github.com/riyadomf/glassfish-hotswap-cli)*

---

## The 60-second cliff

If you've worked on a Jakarta EE app, you know the cycle:

1. Change one line of Java.
2. Save.
3. Wait. Maven builds the WAR. GlassFish undeploys the old version, deploys the new one, re-warms the JPA cache, re-initializes EJBs, finally finishes.
4. By the time the deploy log scrolls past, you've forgotten what you were doing.

On a recent project I clocked it — 47 seconds for the average change. I do this maybe forty times a day. That's half an hour, every day, staring at a deploy log.

The really frustrating part: **most of those changes don't need a redeploy at all.** Tweaking a method body, changing a return value, fixing a logic bug — the JVM is perfectly capable of swapping a single class without restarting anything. The problem is that nobody had wired that capability into a workflow I could actually use from my editor.

So I built one.

## What I tried first

Before writing my own tool, I went through the obvious options:

**IntelliJ's GlassFish plugin.** It does hot-swap, but only inside IntelliJ Ultimate. I bounce between VS Code (for typing speed), Vim (over SSH), and IntelliJ Community (for refactors). I didn't want my fast-feedback loop locked to one editor.

**JRebel.** Excellent tool. Costs €600/year per developer. Hard sell for a side project.

**Plain `asadmin redeploy`.** No improvement over what I already had — it's still a full WAR redeploy.

**HotSwapAgent.** Promising in theory, fiddly in practice. Required JVM-level configuration changes that didn't play well with our team's GlassFish setup, and the documentation assumed you already knew how it worked.

What I actually wanted was a CLI that I could run from any terminal, that recompiled only the files I'd touched, hot-swapped them into the running server when possible, and fell back to a full redeploy when it had to. Nothing existed that did all three.

## The 60-second tour

Here's what `gf` looks like in practice:

```
$ ./gf sync -v
→ Incremental compile (2 files changed)... done in 1.4s
→ JDWP hot-swap (com.example.HelloController)... done in 0.9s
✓ Live in 3.1s. No restart, no redeploy.
```

That's the entire workflow. Edit the file, run one command, the change is live.

There are a few sibling commands — `gf ui` for syncing XHTML/CSS/JS without rebuilding anything, `gf full` when you do need a real redeploy, `gf log --err` for tailing the server log — but `gf sync` is the one I run most of the day.

The full repo is [here](https://github.com/riyadomf/glassfish-hotswap-cli). It's a Bash script plus a single Java file, MIT licensed, designed to be dropped into any Maven + GlassFish 7/8 project.

## How JDWP hot-swap actually works

JDWP — the Java Debug Wire Protocol — is the JVM's built-in debugger protocol. When a JVM is started with `-agentlib:jdwp=transport=dt_socket,server=y,address=*:9009`, it opens a socket and listens for debugger commands. That's what IntelliJ talks to when you set a breakpoint.

The interesting thing about JDWP, and the part that most people don't think about, is that the protocol supports **redefining a class's bytecode in a running JVM**. You connect, you hand it the new bytes for `com.example.HelloController`, and the JVM atomically replaces the existing class definition. Existing instances keep their state. Method bodies that match by signature get the new implementation immediately.

The Java side of that conversation is the JDI — the Java Debug Interface — which lives in the `jdk.jdi` module. The whole thing is about 200 lines of Java. Here's the core of it:

```java
VirtualMachine vm = connector.attach(arguments);  // talk to the JVM

for (Path classFile : changedClassFiles) {
    String className = classFile.toClassName();
    List<ReferenceType> types = vm.classesByName(className);
    if (types.isEmpty()) continue;  // class not loaded yet, skip

    byte[] bytecode = Files.readAllBytes(classFile);
    vm.redefineClasses(Map.of(types.get(0), bytecode));
}

vm.dispose();
```

That's the meat of `tools/HotSwap.java`. The Bash side is doing the orchestration: figuring out which `.java` files changed since the last successful build, running `javac` on just those (incremental compile, with Lombok annotation processing if it's on the classpath), then handing the resulting `.class` files to the Java hot-swap client.

## The interesting bit: when hot-swap can't help

JDWP `redefineClasses` has a limitation. It can change method **bodies**, but it can't change the **shape** of a class. Add a new field, add a new method, change a method signature — the JVM rejects the swap with `UnsupportedOperationException: add method not implemented`.

(There's a JVM flag, `-XX:+AllowRedefinitionToAddDeleteMethods`, that loosens this. But it's still not enough for arbitrary refactors, and it has compatibility gotchas. I decided not to rely on it.)

So `gf` needs a decision tree: try the hot-swap first, fall back to a full redeploy if it fails. But there are actually four cases, not two:

1. **Hot-swap works** → 3-second happy path. Done.
2. **Hot-swap fails with "structural change"** → fall back to `mvn clean package` + `asadmin redeploy`. Slow (~45s) but correct.
3. **Can't connect to JDWP port at all** → either GlassFish isn't in debug mode, or an IDE debugger is already attached holding the port. These need different responses.
4. **JVM doesn't support `canRedefineClasses`** → something's wrong with the debug-options config. Print a diagnostic and bail.

Distinguishing case 2 from case 3 turned out to matter a lot. If I always fell back to a full redeploy when JDWP failed, then attaching IntelliJ's debugger — which holds the port — would trigger an unwanted 45-second redeploy every time I ran `gf sync`. That defeats the whole point.

The fix was simple but only obvious in hindsight: use different exit codes from the Java side. `exit 1` for structural change, `exit 2` for connection failure. The Bash script reads the exit code and branches:

```bash
java -cp tools HotSwap "$DEBUG_PORT" target/classes "$SINCE" $VERBOSE_FLAG
case $? in
    0) ;;  # success
    1) full_redeploy ;;  # structural change
    2) warn "IDE debugger attached — use IDE's hot-swap (Ctrl+F10) instead" ;;
esac
```

Tiny detail. Huge quality-of-life difference.

## What I learned

A few things that surprised me along the way:

**Bash robustness is mostly about defaults.** `set -euo pipefail` at the top of every script catches an absurd number of bugs that would otherwise silently swallow errors. `rsync` errors in particular love to slip past `set -e` because they exit non-zero on the most boring conditions (e.g. an optional directory not existing). I ended up wrapping `rsync` calls with explicit error-to-warning handling instead of letting them kill the script.

**Idempotency is worth the effort.** The companion `setup-glassfish-resources.sh` script creates JDBC pools, JMS queues, and JNDI resources from a properties file. The first version of that script was a 100-line wall of `asadmin create-*` commands. If you ran it twice, you got "resource already exists" errors and the script aborted half-way through, leaving GlassFish in an inconsistent state.

Rewriting it to check-then-create — exists? skip. doesn't exist? create — was annoying. But it means you can run the script any time without thinking, and that's the difference between a tool people actually use and a tool they're afraid of.

**Auto-detection beats configuration.** I started with environment variables for everything. Java version, Maven wrapper path, Lombok presence, GlassFish domain name. Then I realized: every single one of those is derivable from the project itself. The `pom.xml` tells you the Java version. The presence of `mvnw` tells you which Maven to use. A `Lombok` dependency tells you whether to enable annotation processing. By the time I was done, the only required setup was "put GlassFish on your PATH." Everything else just works.

## Try it

If you work on Jakarta EE apps with GlassFish, give `gf` a try:

```bash
curl -fsSL https://raw.githubusercontent.com/riyadomf/glassfish-hotswap-cli/main/gf -o gf
chmod +x gf
./gf run
```

The full README walks through setup. It's MIT licensed, drop-in for Maven + GlassFish 7/8 projects, and works on Linux and macOS.

If you find it useful, a star on the repo means a lot — it helps the project show up for the next person looking for the same thing.

If something doesn't work, open an issue. I'm watching.

🔗 [github.com/riyadomf/glassfish-hotswap-cli](https://github.com/riyadomf/glassfish-hotswap-cli)
