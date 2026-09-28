#!/bin/sh
# Frees the API port before a dev server starts, so `npm run start:dev` cannot die on EADDRINUSE.
#
# The recurring cause is not a busy port, it is an ORPHANED WATCHER. `nest start --watch` runs the
# compiled server as a child process; when the watcher is left behind — a closed terminal, a
# backgrounded run, a second one started by mistake — the child keeps LISTENing, and every later
# start collides with it. Killing only the child is not enough: the stale watcher rebuilds on the
# next file change and spawns a replacement that takes the port straight back. So the watcher that
# owns the listener goes too.
#
# Scoped to THIS api directory and to the process actually holding the port: it never touches an
# unrelated Node server that happens to be on the same number.

PORT="$APP_PORT"
if [ -z "$PORT" ] && [ -f .env ]; then
  PORT=$(sed -n 's/^APP_PORT=//p' .env | tail -n 1 | tr -d '"'"'"' \t\r')
fi
if [ -z "$PORT" ]; then
  echo "free-port: no APP_PORT in the environment or .env — nothing to free"
  exit 0
fi

holders() { lsof -ti tcp:"$PORT" -sTCP:LISTEN 2>/dev/null; }

PIDS=$(holders)
if [ -z "$PIDS" ]; then
  exit 0
fi

# The watcher behind each listener, if that is what the parent turns out to be.
TARGETS="$PIDS"
for pid in $PIDS; do
  parent=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  [ -z "$parent" ] && continue
  case "$(ps -o command= -p "$parent" 2>/dev/null)" in
    *node_modules/.bin/nest*) TARGETS="$TARGETS $parent" ;;
  esac
done

echo "free-port: port $PORT is held by:$(echo " $TARGETS" | tr '\n' ' ') — stopping them"
# SIGTERM first: the server closes its connections instead of leaving the socket in the kernel.
kill $TARGETS 2>/dev/null

# A TERM that has not landed yet is exactly what makes a plain `kill` race the bind that follows,
# so wait for the port to actually come free rather than assuming it did.
i=0
while [ "$i" -lt 30 ]; do
  sleep 0.1
  if [ -z "$(holders)" ]; then
    exit 0
  fi
  i=$((i + 1))
done

echo "free-port: still held after 3s — forcing"
kill -9 $(holders) 2>/dev/null
sleep 0.3
