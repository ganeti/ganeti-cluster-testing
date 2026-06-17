#!/bin/bash
# Archive each running KVM QA guest's serial console to a per-instance
# logfile. Ganeti exposes every instance's serial port as a
# "server,nowait" UNIX socket at <ctrl-dir>/<instance>.serial (only when
# the instance is started with serial_console=true). We attach a socat
# client to each socket - exactly like `gnt-instance console` does - and
# append everything the guest writes to /var/log/ganeti/guest-serial/.
#
# run-cluster-test.py scp's the whole /var/log/ganeti tree from every node
# into the QA run archive, so these logs become browsable per run without
# any extra plumbing.
#
# This is a diagnostics helper: it does not rotate the logfiles (QA runs
# are time-bounded) and only ever reads from the guest - it never writes
# back to the serial port (socat -u is unidirectional, source -> sink).
set -u

CTRL_DIR=/var/run/ganeti/kvm-hypervisor/ctrl
LOG_DIR=/var/log/ganeti/guest-serial
POLL_INTERVAL=2

mkdir -p "$LOG_DIR"

# Map of serial socket path -> pid of the socat capturing it.
declare -A PIDS

cleanup() {
  for pid in "${PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  exit 0
}
trap cleanup TERM INT

while :; do
  shopt -s nullglob

  # Start a capture for every serial socket that is not being captured yet.
  for sock in "$CTRL_DIR"/*.serial; do
    pid=${PIDS["$sock"]:-}
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      continue
    fi
    name=$(basename "$sock" .serial)
    socat -u "UNIX-CONNECT:$sock" \
      "OPEN:$LOG_DIR/$name.log,creat,append" >/dev/null 2>&1 &
    PIDS["$sock"]=$!
  done

  # Forget captures whose socket is gone (instance stopped or migrated
  # away); their socat has already exited on the closed connection.
  for sock in "${!PIDS[@]}"; do
    if [[ ! -S "$sock" ]]; then
      kill "${PIDS[$sock]}" 2>/dev/null || true
      unset 'PIDS[$sock]'
    fi
  done

  sleep "$POLL_INTERVAL"
done
