---
name: investigating
description: Find the cause of a wrong result, crash, or unexpected behaviour in the pricing library. Use when asked why a value is wrong, why the process crashed, or which code produced a given result.
---

# Investigating a bug

## Rules

- NEVER add a log line, print, or assert to source code to find out where
  control goes. Use the scripts below.
- NEVER invoke `cdb` directly or compose your own debugger commands. If the
  three scripts cannot answer the question, say so and stop.

## Step 1 — Frame it

Write these three lines before running anything:

    SYMPTOM:  <what is wrong, and what was expected>
    SUSPECTS: <three candidate causes, most likely first>
    CHECK:    <the one script run that separates suspect 1 from the others>

Consult `docs/functor-index.md` while forming suspects. It lists dispatch
resolutions and is more reliable than reading source, because virtual dispatch
and the functor registry mean the implementation that runs is often not the one
the code suggests.

If all three suspects are eliminated, do not improvise a fourth. Write a new
SUSPECTS line and start again from Step 2. If a second round also eliminates
everything, report what you have ruled out and stop.

## Step 2 — Run one script

First argument is always the build config (`checked` or `optimised`). Run from
the repo root.

**Which implementation runs, and who calls it**

    bash scripts/where-called.sh checked Discounter::df --trade 12345

**What ran, in order, through a subsystem**

    bash scripts/trace-calls.sh checked 'Discounter::*' --trade 12345

Start narrow. `'*::*'` sets tens of thousands of breakpoints and takes minutes.

**Where it crashed or threw**

    bash scripts/on-crash.sh checked --trade 12345

`TRACE_THROWS=1` also prints the stack at each C++ throw, showing the raise
site before unwinding. Noisy if the code throws during normal operation.

Run one script, read it, update SUSPECTS. Do not chain runs speculatively.

## Step 3 — Read the output correctly

Read `STOP REASON` before reading any stack.

| STOP REASON | Meaning | Action |
|---|---|---|
| Break instruction exception | Breakpoint hit | Stack is valid, proceed |
| Any other exception | Stopped for a different reason | Stack shows THAT event, not your breakpoint. Do not report it as a call path |
| Process exited | Run completed | Any stack shown is meaningless |

Frames are listed callee-first: the caller of your target is the frame BELOW it.

Hex addresses instead of function names mean symbols did not load. Report that
and stop. Do not interpret addresses.

## Step 4 — Narrow with the activity log, if one exists

- Investigate only the EARLIEST differing row on replay. Later differences are
  usually consequences of it.
- Skip diffs listed in `docs/replay-notes.md` as benign (timestamps, addresses,
  iteration order).
- Shrink the log to the smallest set of rows that still reproduces the
  difference before analysing in detail.

## Step 5 — Confirm before concluding

A suspicious line is not a proven cause. Report in this form:

    CAUSE:     <the defect>
    EVIDENCE:  <the script output that shows it>
    RULES OUT: <how suspects 2 and 3 were eliminated>

If RULES OUT cannot be filled in, report the finding as UNCONFIRMED. Do not
present a plausible guess as a conclusion.

## Step 6 — Record what was learned

Append to `docs/bugs.md`: symptom, root cause, functor, one line.

If a script corrected a call path that reading the source got wrong, add that
dispatch resolution to `docs/functor-index.md`. That is what prevents the same
wrong guess next time.
