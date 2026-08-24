#!/bin/bash
# Args: <timeout_seconds> <output_file> <pid_file> <claude_executable> [claude args...]
#
# Spawns the given executable (with its remaining args) as the leader of a
# new process group, waits up to <timeout_seconds> for it to exit, and
# SIGKILLs the whole process group if it has not exited by then. Both this
# watchdog and its child are meant to be launched via
# ProcessStartMode.detached from Dart, so neither is a child of the Pro Orc
# process and neither is killed when Pro Orc quits — the watchdog's own
# lifetime (not Pro Orc's) is what enforces the timeout bound.
#
# <pid_file> is written with the child's PID immediately after it is
# backgrounded — this is how the Dart caller (which cannot see inside this
# detached shell) learns the real `claude -p` PID deterministically,
# without racing a poll loop against a short (test-injected) timeout.
#
# No user-controlled value is interpolated into this script's TEXT (the
# script itself is a fixed, code-owned file, never rewritten per-run) — all
# values arrive as discrete argv entries, never shell-evaluated.
set -u

TIMEOUT="$1"
OUTFILE="$2"
PIDFILE="$3"
shift 3

# `set -m` turns on job control in this (non-interactive) shell, which makes
# bash place each backgrounded pipeline in its own process group headed by
# that pipeline's PID — exactly the "claude -p is the group leader" property
# the SIGKILL step below relies on (verified on macOS's default /bin/bash,
# which does not ship `setsid`).
set -m
"$@" > "$OUTFILE" 2>&1 &
CHILD_PID=$!
echo "$CHILD_PID" > "$PIDFILE"

(
  sleep "$TIMEOUT"
  # Negative PID = signal the whole process group, not just the leader —
  # covers any helper process claude -p itself spawns.
  kill -KILL -- "-$CHILD_PID" 2>/dev/null
) &
WATCHDOG_TIMER_PID=$!

wait "$CHILD_PID"
CHILD_EXIT=$?

# Child exited on its own — cancel the timeout kill, it must not fire late
# and hit an unrelated process that later reuses this process group's PID.
kill "$WATCHDOG_TIMER_PID" 2>/dev/null
wait "$WATCHDOG_TIMER_PID" 2>/dev/null

exit "$CHILD_EXIT"
