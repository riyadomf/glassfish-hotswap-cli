## What's in this PR

<!-- One or two sentences describing the change. -->

## Why

<!-- The motivation. Bug fix? New capability? Link the issue if there is one. -->

## How I tested it

<!-- What did you run, against what kind of project, and what did you observe?
     For hot-swap changes, mention which kinds of edits you tested (method body, new method, new field). -->

## Checklist

- [ ] `shellcheck` passes on any changed Bash scripts
- [ ] `javac -Xlint:all tools/HotSwap.java` succeeds if Java was touched
- [ ] `CHANGELOG.md` updated under `[Unreleased]` if user-visible
- [ ] README updated if behavior or commands changed
