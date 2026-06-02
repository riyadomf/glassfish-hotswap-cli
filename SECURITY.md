# Security Policy

## Supported versions

`gf` is a single-script developer tool. Security fixes land on the latest tagged release on `main`. Older tags are not patched.

## Reporting a vulnerability

If you find a security issue, **please don't open a public GitHub issue**. Instead, choose either:

- **GitHub Security Advisories**, the preferred path. Go to the repo's [Security tab](https://github.com/riyadomf/glassfish-hotswap-cli/security/advisories/new) and open a private advisory. This keeps the report confidential until a fix is ready.
- **Email**, `riyad.omf@gmail.com`. Subject line: `[gf security] <short description>`.

Please include:

- A description of the issue and the potential impact.
- Steps to reproduce it (a minimal example is ideal).
- Any suggested mitigation, if you have one.

I'll acknowledge your report within a few days and work on a fix. Once a patch is available, I'll credit you in the release notes unless you prefer to stay anonymous.

## Scope

`gf` runs against a local GlassFish instance and uses `javac`, `rsync`, `asadmin`, and JDWP. The most likely classes of issue:

- Command injection via filenames, paths, or properties values.
- Insecure defaults that expose JDWP or database credentials.
- Unsafe handling of `db.properties` / `env.properties` content.

If you spot something in any of those areas, please report it.
