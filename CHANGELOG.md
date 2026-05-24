# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] — 2026-05-24

First public release. `gf` is now stable, documented, and ready for general use against GlassFish 7 and 8.

### Added

- Incremental Java compilation — only recompiles `.java` files changed since the last successful build (~3–6s).
- JDWP hot-swap via a custom JDI client (`tools/HotSwap.java`). Redefines changed classes in-place without restarting the server.
- UI file sync (`./gf ui`) — `rsync` for XHTML, CSS, JS, images, and JasperReports `.jrxml` templates into the exploded deployment.
- One-command server lifecycle: `./gf run`, `start`, `stop`, `restart`.
- Automatic fallback to full Maven build + redeploy when hot-swap can't handle a structural change.
- Detection of attached IDE debuggers — `gf classes` defers to the IDE's hot-swap instead of fighting for the JDWP port.
- `./gf setup [--delete]` — idempotent GlassFish resource setup (JDBC connection pools, JNDI custom resources, optional JMS) driven by `db.properties` and `env.properties`.
- Auto-sync of JNDI custom resources on `./gf deploy` / `./gf full` — adding a key to `env.properties` is enough.
- Configurable JNDI namespace via `GF_JNDI_PREFIX` (default: `app`).
- Auto-detection of `mvnw`/`mvn`, the Java release version from `pom.xml`, and Lombok on the classpath.
- Cross-platform support for Linux and macOS.
- Claude Code skill (`.claude/skills/gf/`) that exposes the whole workflow via the `/gf` slash command.
- Sample configuration templates (`db.properties.sample`, `env.properties.sample`) with inline guidance and `chmod 600` reminders.
- `ensure_asadmin_ready` probe — every command that talks to `asadmin` now fails fast with actionable guidance (`asadmin login` / `asadmin change-admin-password`) when authentication is missing or invalid, instead of crashing silently under `set -e`. Mirrored in `setup-glassfish-resources.sh`.
- Troubleshooting entry in the README for the `asadmin: Authentication failed for user: null` case.

### Changed

- Self-healing JDWP debug options in `domain.xml` on startup, so a broken debug config doesn't block `./gf start`.
- `gf`'s own status lines (`info` / `success` / `warn` / `error`) are now bold, so they stand out from Maven's regular-weight `[INFO]` output streaming alongside.
- All `asadmin deploy` invocations now pass `--upload=true`, which makes deployments work whether the admin endpoint is anonymous-local or auth-protected with `secure-admin` enabled.
- Maven `clean package` builds in `cmd_deploy` and `cmd_full` no longer use `-q` — build progress is visible to the user while they're waiting on it.

### Fixed

- `find_app_name()` now consults `asadmin list-applications` when the exploded directory is missing — catches "ghost" registrations.
- Incremental `javac` now warns when neither `maven.compiler.release` nor `maven.compiler.source` is set, instead of silently using the system default.
- `rsync` errors in sync functions are surfaced as warnings instead of killing the script under `set -e`.
- `ping-connection-pool` failures during resource setup no longer abort the rest of the setup.
- `find_app_name` and `create_custom_resources` no longer swallow `asadmin` errors with `2>/dev/null`; underlying failures (auth, connectivity) now reach the user instead of producing empty results.

[Unreleased]: https://github.com/riyadomf/glassfish-hotswap-cli/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/riyadomf/glassfish-hotswap-cli/releases/tag/v1.0.0
