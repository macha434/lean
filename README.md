# haiku-shunt

A Claude Code plugin that keeps bulk file reading and boilerplate generation out
of your main conversation by shunting them to Haiku subagents.

[日本語版 README](README.ja.md)

## Overview

- Target users: Claude Code users whose token usage is dominated by reading
  large files and generating mechanical code.
- Problem solved: a 2,000-line file read in the main conversation stays in
  context for the rest of the session, and every subsequent turn pays for it.
- Value: the same file read inside a subagent costs one summary. Only the
  answer reaches your conversation; the file itself is discarded.

This is a single-vendor take on the approach Spotify described when they cut
Claude Code token usage by ~90%. Their `shunt` plugin routes bulk work to
Gemini Flash through Spotify's internal Portal platform. This one does the same
thing with Claude Haiku and nothing else, so it works for anyone with a plain
Claude Code install.

## Key Features

- **A hook that makes it automatic.** Large whole-file reads in the main
  conversation are blocked with a message telling Claude to delegate instead.
  You do not have to remember the policy.
- **`bulk-reader`** — a Haiku subagent that reads files in its own disposable
  context and returns only the extract that answers your question.
- **`code-writer`** — a Haiku subagent that writes settled, mechanical code
  straight to disk and reports paths, so generated code never enters your
  context at all.
- **Fails open, always.** Missing `jq`, unreadable paths, malformed hook input:
  every failure path allows the read. A cost optimisation should never be the
  reason a session stops working.

## How it works

Three layers, matching the structure Spotify used:

| Layer | File | Role |
|---|---|---|
| Hook | `hooks/check-file-size.sh` | Intercepts `Read`, blocks whole-file reads over the threshold |
| Agents | `agents/*.md` | Do the bulk work on `model: haiku` |
| Skill | `skills/delegating-bulk-work/` | Tells Claude to delegate *before* it hits the hook |

The hook allows the call — never blocks — when any of these hold:

- it is running inside a subagent (`agent_id` is present), so the delegate
  itself always reads freely and there is no loop;
- the read is bounded by `offset` or `limit`, since a targeted read is already
  what we want;
- the file is binary, missing, unreadable, or under the line threshold.

## Requirements

- Claude Code with plugin support
- `jq` — without it the hook allows everything and the plugin does nothing

## Setup

```bash
claude plugin marketplace add macha434/haiku-shunt
claude plugin install haiku-shunt@macha434-plugins
```

## Usage

Nothing to invoke. Once installed, reading a large file in the main
conversation is redirected:

```
haiku-shunt: src/app/routes.ts is 1,240 lines (threshold 350).
Reading it in full would load all of it into this conversation's context.

Delegate it instead: call the Task/Agent tool with subagent_type "bulk-reader"...
```

You can also delegate explicitly at any time:

> Use the bulk-reader agent to find where the retry policy is configured in
> `src/http/`.

> Use the code-writer agent to add table-driven tests for `parseDuration`.

## Configuration

Both are read from the environment at hook time.

| Variable | Default | Effect |
|---|---|---|
| `HAIKU_SHUNT_MIN_LINES` | `350` | Line count at or above which a whole-file read is blocked. A non-numeric value falls back to the default. |
| `HAIKU_SHUNT_DISABLE` | unset | Set to `1` to allow every read and disable the hook. |

## Development

```bash
tests/run-tests.sh
```

The suite drives the hook script with recorded `PreToolUse` payloads and
asserts allow/deny for each case, including the fail-open paths.

## FAQ

**Q. Does this block the subagent from reading the file too?**
A. No. `agent_id` appears in the hook payload only inside a subagent, and the
hook allows the call whenever it is present.

**Q. What if I actually need the raw text in the main conversation?**
A. Re-issue the read with `offset`/`limit`. Ranged reads are never blocked.
To turn the hook off entirely, set `HAIKU_SHUNT_DISABLE=1`.

**Q. Is `code-writer` enforced by a hook as well?**
A. No. There is no reliable signal for "this generation is mechanical", so
that half is policy (the skill and the agent description) rather than
enforcement.

## Credits

The three-layer design and the file-size-threshold idea come from
[spotify/portal-ai-plugins](https://github.com/spotify/portal-ai-plugins).

## License

MIT
