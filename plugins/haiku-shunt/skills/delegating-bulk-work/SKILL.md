---
name: delegating-bulk-work
description: Policy for keeping bulk file reading and boilerplate generation out of the main conversation by delegating them to cheaper subagents. Use when about to read a long file, survey many files, or generate scaffolding, tests, fixtures, or other mechanical code.
---

# Delegating bulk work

Two kinds of work dominate token usage without needing the main model's
judgement: reading large amounts of text, and typing out code whose shape is
already decided. Both belong in a subagent, where the bulk stays in a context
that is thrown away.

## Reading

Delegate to `bulk-reader` when you are about to:

- read a file over a few hundred lines,
- read several files to answer one question,
- search a codebase where you do not yet know which file holds the answer.

Give it the absolute path (or the search target) **and the specific question**.
A vague brief comes back as a vague summary, and you pay for it twice when you
have to ask again.

Read directly when the file is short, when you need the exact text to edit it,
or when you already know the few lines you want - use `offset`/`limit` for
that. A bounded read is not worth delegating.

## Writing

Delegate to `code-writer` when the design is settled and only the typing is
left: test skeletons, fixtures, scaffolding, config, repetitive edits across
files. It writes to disk and reports paths, so the generated code never enters
this conversation.

Keep work here when it involves a decision: interface design, debugging,
anything where you need to see the result to judge it.

## The rule behind both

Delegate the volume, keep the judgement. If a task is large but mechanical, it
belongs in a subagent. If it is small but consequential, it belongs here.
