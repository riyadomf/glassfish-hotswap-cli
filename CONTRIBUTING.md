# Contributing to `gf`

Thanks for your interest in making `gf` better! This is a small, focused project — contributions of any size are welcome.

## Reporting bugs

Open an issue using the bug report template. Please include:

- Your **GlassFish version** (`asadmin version`)
- Your **Java version** (`java -version`)
- Your **OS** (Linux distribution, macOS version)
- The **command you ran** and what you expected to happen
- The **actual output** (full output if possible — most `gf` commands accept `-v` for verbose mode)

If the issue involves hot-swap behavior, knowing which kind of change you were trying to swap (method body, new field, new method, class signature) is very helpful.

## Suggesting features

Open an issue using the feature request template, or start a thread in [Discussions](https://github.com/riyadomf/glassfish-hotswap-cli/discussions) if you'd like to talk through an idea first.

`gf` deliberately stays small — it's a workflow tool, not a deploy framework. Features that fit well: faster feedback loops, better fallback behavior, support for more GlassFish/Jakarta EE scenarios. Features that probably don't fit: anything that turns `gf` into a build tool or replaces Maven.

## Submitting pull requests

1. Fork the repo and create a branch off `main`.
2. Make your change. Keep PRs focused — one logical change per PR is much easier to review.
3. If you're touching the Bash code, run [`shellcheck`](https://www.shellcheck.net/) locally on the script you changed.
4. If you're touching `tools/HotSwap.java`, make sure it still compiles with `javac -Xlint:all`.
5. Open the PR using the template. Explain *what* changed, *why*, and *how you tested it*.

CI will run `shellcheck` and the Java compile check automatically.

## Code style

**Bash:**
- Use `set -euo pipefail` at the top of any new script.
- Prefer `[[ ]]` over `[ ]` for tests.
- Quote variable expansions: `"$VAR"`, not `$VAR`.
- Local variables in functions: `local foo=bar`.

**Java:**
- Standard conventions. The codebase is small (one file) — match the existing style.

**Commit messages:**
- Use the existing pattern: short imperative subject line, optional body explaining *why*.
- Examples from the existing log: `Add setup command and JNDI resource auto-sync`, `Harden rsync error handling in sync functions`, `Fix asadmin fallback in find_app_name()`.

## Local testing

There's no automated test suite — `gf` is integration-heavy and needs a real GlassFish to be meaningful. The fastest way to test a change is:

1. Have a GlassFish install and a Maven Jakarta EE project handy (the kind `gf` is meant to be used with).
2. Run the affected `gf` command from that project and check it behaves as expected.
3. For hot-swap changes specifically, try all three cases: method-body change (should hot-swap), new method (should fall back to full redeploy), no change at all (should be a no-op).

If you don't have a test project, mention that in the PR — a maintainer can verify against theirs.

## Questions?

Open a [Discussion](https://github.com/riyadomf/glassfish-hotswap-cli/discussions) — for anything that isn't a clear bug or feature request, Discussions is the right place.
