# ![ex_check](./assets/logo-with-name.svg)

[![Hex version](https://img.shields.io/hexpm/v/ex_check.svg?color=hsl(265,40%,60%))](https://hex.pm/packages/ex_check)
[![Hex docs](https://img.shields.io/badge/hex-docs-lightgreen.svg?color=hsl(265,40%,60%))](https://hexdocs.pm/ex_check/)
[![Build status](https://img.shields.io/github/actions/workflow/status/karolsluszniak/ex_check/check.yml?branch=master)](https://github.com/karolsluszniak/ex_check/actions)
[![Downloads](https://img.shields.io/hexpm/dt/ex_check.svg)](https://hex.pm/packages/ex_check)
[![License](https://img.shields.io/github/license/karolsluszniak/ex_check.svg)](https://github.com/karolsluszniak/ex_check/blob/master/LICENSE.md)
[![Last updated](https://img.shields.io/github/last-commit/karolsluszniak/ex_check.svg)](https://github.com/karolsluszniak/ex_check/commits/master)

![Demo](./assets/demo-67x16.svg)

**Get fast feedback with `mix check`, then run the authoritative suite with `mix check --full`.**

---

Takes seconds to setup, saves hours in the long term.
- Comes out of the box with a [predefined set of curated tools](https://hexdocs.pm/ex_check/Mix.Tasks.Check.html#module-tools)
- Delivers results faster by [running tools in parallel and catching all issues in one go](https://hexdocs.pm/ex_check/Mix.Tasks.Check.html#module-workflow)
- Selects affected ExUnit tests from content snapshots and the compiler graph, with conservative full-suite fallbacks
- Keeps expensive tools such as Dialyzer, Sobelow, and dependency audit in the [full check](https://hexdocs.pm/ex_check/Mix.Tasks.Check.html#module-fast-and-full-checks)
- Runs formatter, Credo, and configurable aggregate tools only for content changed since each tool's last successful run
- Checks the project consistently before commits and [on CI](https://github.com/karolsluszniak/ex_check#continuous-integration)
- Runs only the tools & tests that have [failed in the last run](https://hexdocs.pm/ex_check/Mix.Tasks.Check.html#module-retrying-failed-tools)
- Fixes issues automatically in [the fix mode](https://hexdocs.pm/ex_check/Mix.Tasks.Check.html#module-fix-mode)

Sports powerful features to enable ultimate flexibility.
- Add custom mix tasks, shell scripts and commands via [configuration file](https://hexdocs.pm/ex_check/Mix.Tasks.Check.html#module-configuration-file)
- Gate aggregate tools on staged, unstaged, and untracked inputs without requiring a persistent server
- Enhance you CI workflow to [report status](https://hexdocs.pm/ex_check/Mix.Tasks.Check.html#module-manifest-file), [retry random failures](#random-failures) or [autofix issues](#autofixing)
- Empower umbrella projects with [parallel recursion over child apps](https://hexdocs.pm/ex_check/Mix.Tasks.Check.html#module-umbrella-projects)
- Design complex parallel workflows with [cross-tool deps](https://hexdocs.pm/ex_check/Mix.Tasks.Check.html#module-cross-tool-dependencies)

Takes care of the little details, so you don't have to.
- Compiles the project and collects compilation warnings in one go
- Ensures that output from tools is [ANSI formatted & colorized](https://hexdocs.pm/ex_check/Mix.Tasks.Check.html#module-tool-processes-and-ansi-formatting)
- Reprints failures together at the end when desired (toggle with `--no-reprint` or `reprint: false`)
- Retries ExUnit with the `--failed` flag
- Can stop immediately after the first failure with `--fail-fast`
- Recovers abandoned lock files automatically after about 10 seconds without disabling locking

Read more in the introductory ["One task to rule all Elixir analysis & testing tools"](https://cloudless.studio/one-task-to-rule-all-elixir-analysis-testing-tools) article.

## Getting started

Add `ex_check` dependency in `mix.exs`:

```elixir
def deps do
  [
    {:ex_check, "~> 0.16.0", only: [:test], runtime: false}
  ]
end
```

Fetch the dependency:

```
mix deps.get
```

Run the fast iterative check:

```
mix check
```

Before a commit, and on CI, run the authoritative check:

```
mix check --full
```

The fast check compiles first, runs inexpensive tools, and selects affected tests. The full check
ignores retry narrowing, enables full-only tools, and forces every ExUnit test to run. When you want
to inspect test selection while it runs, use `mix check --debug`; use `mix check --explain` to see
the same details without executing tests. Normal runs omit impact-selection diagnostics.

In debug mode, when an unqualified full check follows a successful unqualified fast check that also
ran with `--debug` for the exact same content generation, ex_check reports whether the
authoritative suite exposed a fast miss. Ordinary runs neither record nor report this comparison.

### Community tools

If you want to take advantage of community curated tools, add following dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:credo, ">= 0.0.0", only: [:test], runtime: false},
    {:dialyxir, ">= 0.0.0", only: [:test], runtime: false},
    {:doctor, ">= 0.0.0", only: [:test], runtime: false},
    {:ex_doc, ">= 0.0.0", only: [:dev], runtime: false},
    {:gettext, ">= 0.0.0", only: [:test], runtime: false},
    {:sobelow, ">= 0.0.0", only: [:test], runtime: false},
    {:mix_audit, ">= 0.0.0", only: [:test], runtime: false}
  ]
end
```

You may also generate `.check.exs` to adjust the check:

```
mix check.gen.config
```

Among others, this allows to permanently disable specific tools and avoid the skipped notices.

```elixir
[
  tools: [
    {:dialyzer, false},
    {:sobelow, false}
  ]
]
```

### Local-only fix mode

You should keep local and CI configuration as consistent as possible by putting together the project-specific `.check.exs`. Still, you may introduce local-only config by creating the `~/.check.exs` file. This may be useful to enforce global flags on all local runs. For example, the following config will enable the fix mode in local (writable) environment:

```elixir
[
  fix: true
]
```

> You may also [enable the fix mode on the CI](#autofixing).

## Documentation

Learn more about the tools included in the check as well as its workflow, configuration and options [on HexDocs](https://hexdocs.pm/ex_check/Mix.Tasks.Check.html) or by running `mix help check`.

Want to write your own code check? Get yourself started by reading the ["Writing your first Elixir code check"](https://cloudless.studio/writing-your-first-elixir-code-check) article.

## Continuous Integration

With `mix check --full` you can consistently run the authoritative set of checks before commits and on CI. CI configuration also comes out of the box with parallelism and error output from all checks at once regardless of which ones have failed.

Run `mix check --full` instead of `mix test`. Do not use the fast default as a merge or release gate. This repo features a working CI config for:

- GitHub - [.github/workflows/check.yml](https://github.com/karolsluszniak/ex_check/blob/master/.github/workflows/check.yml)

Yes, `ex_check` uses itself on the CI. Yay for recursion!

### Autofixing

You may automatically fix and commit back trivial issues by triggering the fix mode on the CI as well. In order to do so, you'll need a CI script or workflow similar to the example below:

```bash
mix check --fix && \
  git diff-index --quiet HEAD -- && \
  git config --global user.name 'Autofix' && \
  git config --global user.email 'autofix@example.com' && \
  git add --all && \
  git commit --message "Autofix" && \
  git push
```

First, we perform the check in the fix mode. Then, if no unfixable issues have occurred and if fixes were actually made, we proceed to commit and push these fixes.

Of course your CI will need to have write permissions to the source repository.

### Random failures

You may take advantage of the automatic retry feature to efficiently re-run failed tools & tests multiple times during development. For instance, following shell command runs check up to three times: `mix check || mix check || mix check`. And here goes an alternative without the logical operators:

```bash
mix check
mix check --retry
mix check --retry
```

This will work as expected because the `--retry` flag will ensure that only failed tools are executed, resulting in no-op if previous run has succeeded.

Full checks never retry narrowly. `mix check --full --retry` is rejected because it would make the
meaning of the authoritative command ambiguous.

## Troubleshooting

### A single test build

The fast test selector and its compiler manifests belong to `MIX_ENV=test`. Run `mix check` and all
the tools it depends on in that environment to avoid duplicate dev/test compilation. Configure the
task and dependencies as follows when your project does not already use a single test build:

```elixir
def project do
  [
    # ...
    preferred_cli_env: [
      check: :test,
      credo: :test,
      dialyzer: :test,
      doctor: :test,
      sobelow: :test,
      "deps.audit": :test
    ]
  ]
end

def deps do
  [
    {:credo, ">= 0.0.0", only: [:test], runtime: false},
    {:dialyxir, ">= 0.0.0", only: [:test], runtime: false},
    {:doctor, ">= 0.0.0", only: [:test], runtime: false},
    {:ex_check, "~> 0.14.0", only: [:test], runtime: false},
    {:ex_doc, ">= 0.0.0", only: [:dev, :test], runtime: false},
    {:sobelow, ">= 0.0.0", only: [:test], runtime: false},
    {:mix_audit, ">= 0.0.0", only: [:test], runtime: false}
  ]
end
```

And the following in `.check.exs`:

```elixir
[
  tools: [
    {:compiler, env: %{"MIX_ENV" => "test"}},
    {:formatter, env: %{"MIX_ENV" => "test"}},
    {:ex_doc, env: %{"MIX_ENV" => "test"}}
  ]
]
```

Above setup will consistently check the project using just the test build, both locally and on the CI.

### `unused_deps` false negatives

You may encounter an issue with the `unused_deps` check failing on the CI while passing locally, caused by fetching only dependencies for specific env. If that happens, remove the `--only test` (or similar) from your `mix deps.get` invocation on the CI to fix the issue.

## Changelog

See [CHANGELOG.md](./CHANGELOG.md).

## Copyright and License

Copyright (c) 2019 Karol Słuszniak

This work is free. You can redistribute it and/or modify it under the
terms of the MIT License. See the [LICENSE.md](./LICENSE.md) file for more details.
