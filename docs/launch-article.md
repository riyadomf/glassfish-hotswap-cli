*Building a command-line hot-swap workflow for GlassFish using JVM debugging internals: no IntelliJ Ultimate, no JRebel, no custom JVM.*

*Repo: [glassfish-hotswap-cli](https://github.com/riyadomf/glassfish-hotswap-cli)*

{% embed https://github.com/riyadomf/glassfish-hotswap-cli %}

## The 2-minute cliff

If you've worked on a Jakarta EE application running on GlassFish, you probably know this routine.

1. Change a line of Java.
2. Save.
3. Rebuild the WAR.
4. Wait while it undeploys, redeploys, and re-warms CDI, EJBs, JPA, JSF, and everything else.

Then finally refresh the browser.

By the time the deploy log finishes scrolling, you've forgotten what you were testing in the first place.

On a recent enterprise project I decided to measure it.

A normal redeploy averaged around **two minutes**.

Two minutes doesn't sound terrible until you realize how often it happens. Forty redeploys a day is common when you're deep in a feature or chasing a bug. That's well over an hour spent staring at deployment logs instead of writing code.

The frustrating part is that most of those changes don't actually require a redeploy.

Changing a method body. Fixing a conditional. Adjusting a calculation. Returning a different value.

The JVM already knows how to handle those changes. The infrastructure for it has shipped with every JVM since Java 5.

> The JVM has been able to hot-swap classes for nearly two decades. The problem wasn't capability. It was access.

Most hot-swap solutions assume one of three things:

* You're using a specific IDE.
* You're paying for a commercial product.
* You're running a custom JVM.

What I wanted was much simpler.

I wanted a command I could run from a terminal.

Something like:

```bash
./gf sync
```

A command that could be called from Bash, Make, CI pipelines, tmux, SSH sessions, or even an AI coding agent.

Surprisingly, I couldn't find one.

So I built it.

The result is a tiny tool called `gf`.

It's mostly Bash. About 200 lines of Java. And it reduced my feedback loop from roughly two minutes to somewhere between three and six seconds.

Five seconds is the number I use in my head now.



## What I tried first

Before building anything, I tried the obvious options.

### IntelliJ Ultimate

IntelliJ's GlassFish integration supports hot-swap while debugging.

It works.

The catch is that the workflow lives entirely inside IntelliJ Ultimate.

That's fine if everyone on your team already uses Ultimate and never leaves it.

My workflow is different.

Some days I'm in IntelliJ Community. Some days VS Code. Sometimes I'm in a terminal with Claude Code driving the changes while I watch logs in tmux.

I wanted the fast feedback loop to follow me, not the editor.

### JRebel

JRebel is genuinely impressive.

If your company already pays for it, you should absolutely evaluate it.

For smaller teams, side projects, contractors, and junior developers, licensing costs can be a tougher conversation.

I wanted something anybody could clone and use immediately.

### Plain redeploys

This was my baseline.

Nothing wrong with it.

Just slow.

### DCEVM

DCEVM is probably the most technically ambitious solution in this space.

Unlike standard JDWP hot-swap, it can redefine the structure of classes. New methods, new fields, signature changes.

That's powerful.

But it comes with tradeoffs:

* You need a custom JVM build.
* Support for newer JDK releases often arrives later.
* Many enterprise environments don't allow replacing the approved JDK.

I wasn't looking for ultimate flexibility.

I was looking for the fastest path through the most common case.



## A 60-second tour

This is what the workflow looks like now:

![./gf sync -v output](https://raw.githubusercontent.com/riyadomf/glassfish-hotswap-cli/main/docs/demo-sync-output.png)

![glassfish-hotswap-cli demo](https://raw.githubusercontent.com/riyadomf/glassfish-hotswap-cli/main/docs/demo.gif)

That's it.

Edit.

Save.

Run `./gf sync`.

Refresh.

The change is live.

No restart, no redeploy, no context switch.

Most days, `sync` is the only command I use.

If I'm only changing XHTML, CSS, JavaScript, or JasperReports templates, I use `./gf ui`, which skips compilation entirely.

And when I make a structural change that hot-swap can't handle, `./gf full` falls back to a traditional clean build and redeploy.

The important part isn't the command itself.

It's that the workflow lives in the terminal.

Anything that can run a shell command can trigger a hot-swap.

A Makefile.

A script.

A remote SSH session.

A CI hook.

An AI coding agent.

That turned out to be the missing piece.

> The JVM already knew how to hot-swap classes.
>
> IDEs already knew how to talk to the JVM.
>
> What was missing was a simple command-line bridge between the two.



## How JDWP hot-swap actually works

The nice thing about this approach is that there's no magic involved.

Everything relies on functionality already built into the JDK.

JDWP, the Java Debug Wire Protocol, is the same protocol your IDE uses when you attach a debugger.

Start GlassFish with:

```bash
-agentlib:jdwp=transport=dt_socket,server=y,address=*:9009
```

and the JVM opens a debug port waiting for connections.

Most developers use that port for breakpoints.

But JDWP supports something else that's arguably more interesting: redefining class bytecode inside a running JVM.

The process is surprisingly simple:

1. Connect to the running JVM.
2. Find the loaded class.
3. Read the newly compiled bytecode.
4. Ask the JVM to replace the existing implementation.

No restart required.

No new classloader.

No application bootstrap.

Just new code running inside existing objects.

The core implementation ended up being about ten lines of Java:

```java
VirtualMachine vm = connector.attach(arguments);

for (Path classFile : changedClassFiles) {
    String className = classFile.toClassName();

    List<ReferenceType> types =
        vm.classesByName(className);

    if (types.isEmpty()) continue;

    byte[] bytecode =
        Files.readAllBytes(classFile);

    vm.redefineClasses(
        Map.of(types.get(0), bytecode)
    );
}

vm.dispose();
```

The Bash script handles everything around it:

* Detect changed files
* Incremental compilation
* Lombok support
* Error handling
* Deployment fallback

JDWP does the actual class replacement.

There's a side benefit of doing this through JDWP instead of redeploying that took me months to appreciate.

Every redeploy creates a new application classloader.

In large applications, repeated redeploys can gradually accumulate classloader leaks and metaspace growth.

Eventually somebody restarts the domain.

JDWP hot-swap doesn't create a new classloader.

The existing one stays alive.

The class definition changes in place.

I can go an entire day with dozens of code changes and never restart GlassFish.

The domain simply stays healthier.

## The interesting bit: when hot-swap can't help

Of course, there are limits.

Standard JDWP hot-swap can replace method bodies, but it can't change the structure of a class.

Add a new field.

Add a new method.

Change a method signature.

The JVM rejects the update.

You'll typically see something along the lines of:

```text
UnsupportedOperationException: add method not implemented
```

At that point a full redeploy is unavoidable.

The obvious solution would be:

1. Try hot-swap.
2. If it fails, redeploy.

But reality turned out to be a little messier.

There are actually four different situations:

### 1. Hot-swap succeeds

The happy path.

Compile.

Swap.

Refresh.

Done in a few seconds.

### 2. Structural change detected

The JVM rejects the class redefinition.

`gf` falls back to:

```bash
./gf full
```

which performs a normal Maven build and GlassFish redeploy.

Slower, but correct.

### 3. JDWP connection unavailable

This turned out to be more subtle than I expected.

Sometimes the JVM isn't reachable because GlassFish wasn't started in debug mode.

Other times IntelliJ is already attached to the debug port.

Those situations look similar from the outside, but they should lead to very different outcomes.

A missing debug configuration is a setup issue.

An attached IDE debugger means hot-swap is already available elsewhere.

The tool needed to distinguish between them.

The solution ended up being simple: different exit codes.

```bash
java -cp tools HotSwap "$DEBUG_PORT" target/classes "$SINCE"

case $? in
    0) ;;
    1) full_redeploy ;;
    2) warn "Debugger already attached or JDWP unavailable" ;;
esac
```

A tiny implementation detail.

But it prevented unnecessary redeploys and made the workflow feel much smarter.

### 4. JVM configuration issue

Occasionally you'll encounter a JVM that reports:

```java
vm.canRedefineClasses() == false
```

That's usually a configuration problem.

The tool prints diagnostics and exits instead of guessing.



## The JasperReports problem

Hot-swapping Java classes solved most of my feedback loop.

Then I hit JasperReports.

If you've worked on enterprise applications, you've probably seen it.

A report template changes.

Maybe a column moves.

Maybe a calculation changes.

Maybe the customer wants a different logo.

The template lives in a `.jrxml` file somewhere under:

```text
src/main/resources/reports/
```

You make the change.

Generate the PDF.

Nothing happens.

The old report is still there.



At first I assumed IntelliJ's resource update feature would handle it.

It doesn't.

The GlassFish integration understands web resources such as:

* XHTML
* CSS
* JavaScript
* Images

But it doesn't know anything about `.jrxml` templates.

So every report change meant one of two things:

* wait for a full redeploy
* manually copy files into GlassFish's exploded deployment directory

Neither option was particularly appealing.



The first half of the solution was straightforward.

`gf ui` uses `rsync` to copy report templates directly into the exploded deployment:

```text
src/main/resources/reports/
            |
            v
WEB-INF/classes/reports/
```

Now the updated file exists on disk.

Problem solved?

Not quite.



The second half was hiding inside the application itself.

Most JasperReports integrations load templates through the classloader:

```java
getClass().getResourceAsStream(reportPath)
```

That's the correct production implementation.

The problem is that classloaders cache resources.

The first version of the report gets loaded and stays loaded.

Your freshly copied file never gets used.



The workaround ended up being surprisingly clean.

When running from an exploded deployment, resources are served using a `file:` URL.

When running from a packaged WAR, they're served from the classpath.

That means we can detect the environment automatically.

Development uses the filesystem.

Production uses the classloader.

No feature flags.

No environment variables.

No special configuration.

Just:

```java
URL resource = getClass().getResource(reportPath);

if (resource != null &&
    "file".equals(resource.getProtocol())) {

    try (InputStream is =
             Files.newInputStream(
                 Path.of(resource.toURI()))) {

        return JasperCompileManager.compileReport(is);
    }
}
```

One small change.

The feedback loop for report development dropped from minutes to seconds.

> Honestly, this feature alone probably saves me more time than the Java hot-swap itself.



## Why not just use IntelliJ Ultimate?

A fair question.

I already owned a license.

I used it.

And I still built this.

The reason is simple:

> The problem wasn't hot-swap. The problem was workflow.

I wanted the feedback loop to exist independently of any specific IDE.

Some days I'm using IntelliJ.

Some days VS Code.

Sometimes I'm SSH'd into a development box.

Sometimes Claude Code is driving the changes while I'm reviewing logs.

The workflow should stay the same regardless of which editor happens to be open.

A terminal command gives you that portability.

An IDE plugin doesn't.

## A few quality-of-life improvements

Once the core workflow existed, a handful of smaller annoyances became impossible to ignore.

### Automatic JNDI resource creation

New configuration keys often required matching GlassFish resources.

Forgetting one usually meant discovering the problem during deployment.

`gf` now creates missing resources automatically during deployment.

The configuration file remains the source of truth.

### Self-healing debug configuration

Occasionally GlassFish would start with incorrect JDWP settings.

The server looked healthy.

The application worked.

Hot-swap quietly stopped working.

The script now checks and fixes common debug configuration issues before startup.

### Better authentication errors

If you've ever seen:

```text
Authentication failed for user: null
```

you know how unhelpful that message is.

The newer versions detect the problem early and print the exact recovery commands needed.

Small details.

But those details determine whether a tool feels pleasant or frustrating after hundreds of uses.



## Claude Code integration

One unexpected benefit of building a CLI was that AI tooling immediately understood it.

The repository includes a Claude Code skill that exposes the workflow through a `/gf` command.

That means prompts like:

> redeploy the application and watch the logs

become actual commands instead of conversational instructions.

```text
/gf sync -v
/gf full
/gf log --err
```

I didn't originally plan this feature.

Once the workflow was expressed as commands rather than IDE actions, turning it into an agent skill felt like a natural next step.

With the rise of agentic software engineering, tools that expose clear command-line interfaces are much easier for AI systems to understand and use reliably.

> Good command-line interfaces compose well with everything: humans, scripts, CI systems, and now AI agents.



## What I learned

A few lessons kept showing up throughout this project.

### Good defaults beat configuration

My first versions exposed everything as settings.

Java version.

Maven path.

Lombok configuration.

Domain name.

Eventually I realized almost all of it could be detected automatically.

The fewer things users need to configure, the more likely they are to actually use the tool.

### Idempotency matters

The original setup scripts worked exactly once.

Running them twice produced a wall of "already exists" errors.

Nobody likes tools they're afraid to run.

Making setup repeatable turned out to be one of the highest-leverage improvements.

### Bash robustness is mostly about defaults

`set -euo pipefail` at the top of every script catches an absurd number of bugs that would otherwise silently swallow errors.

But it has blind spots.

`rsync` is the one I keep tripping over. It exits non-zero on the most boring conditions, like an optional source directory not existing, and those errors slip right past `set -e`.

I ended up wrapping every `rsync` call with explicit error-to-warning handling instead of letting them kill the script.

Defaults matter. Knowing where the defaults fail matters more.

### Exit codes are part of your API

At first every failure looked the same.

That was a mistake.

A structural hot-swap failure and a connection failure are fundamentally different events.

Once the tool started communicating that distinction clearly, a surprising amount of user confusion disappeared.

### Small delays matter more than we think

Nobody complains about a two-minute redeploy.

Not really.

You get used to it.

You check Slack.

You open another tab.

You wait.

> The cost isn't the two minutes. The cost is losing focus forty times a day.
>
> That's what I wanted back.



## Who this is for

`gf` isn't trying to replace JRebel.

It's not trying to replace IntelliJ.

And it's definitely not trying to solve every hot-reload problem in Java.

It's for a very specific group of developers:

* You run GlassFish 7 or 8.
* You work on a Jakarta EE application.
* Your redeploy cycle is slowing you down.
* You prefer command-line workflows.
* You want something that works with any editor.

If that sounds familiar, you might find it useful.



## Try it

Getting started takes about a minute:

```bash
curl -fsSL https://raw.githubusercontent.com/riyadomf/glassfish-hotswap-cli/main/gf -o gf

mkdir -p tools

curl -fsSL \
https://raw.githubusercontent.com/riyadomf/glassfish-hotswap-cli/main/tools/HotSwap.java \
-o tools/HotSwap.java

chmod +x gf

./gf run
```

After that:

```bash
./gf sync -v
```

becomes your new development loop.

The project is MIT licensed, works on Linux and macOS, supports JDK 17, 21, and 25, and has been my daily driver for the past several months.

The JVM has supported class redefinition for years.

Most developers simply interact with it through an IDE.

I wanted the same capability from a terminal.

That's all this project really is: a thin layer between a running JVM and a developer who wants feedback in seconds instead of minutes.

If that sounds useful, give it a try.

And if you find a bug, open an issue. I'd love to hear about your workflow and how you're using it.

**GitHub:** [glassfish-hotswap-cli](https://github.com/riyadomf/glassfish-hotswap-cli)
