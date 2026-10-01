#!/usr/bin/env bash
set -euo pipefail
# Ubuntu loopback only: the domain proxy reaches the Mac gateway over SSH.
# SSH port 6001 is supplied by the existing frpc visitor.
exec /usr/bin/ssh -N -T -p 6001 \
  -o BatchMode=yes -o ExitOnForwardFailure=yes \
  -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
  -R 127.0.0.1:18787:127.0.0.1:8787 yzq@127.0.0.1
