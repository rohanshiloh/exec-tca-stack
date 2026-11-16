#!/bin/sh
# exec-tca-stack : fetch the KX tickerplant, which this repository does not redistribute.
# Run once, from the repository root:   ./setup.sh
set -e
tmp=$(mktemp -d)
git clone --depth 1 https://github.com/KxSystems/kdb-tick "$tmp/kdb-tick"
mkdir -p tick log
cp "$tmp/kdb-tick/tick.q" .
cp "$tmp/kdb-tick/tick/u.q" "$tmp/kdb-tick/tick/r.q" tick/
curl -sL https://raw.githubusercontent.com/KxSystems/kdb/master/tick/chainedtick.q -o tick/chainedtick.q
ln -sf ../sym.q tick/sym.q      # tick.q loads its schema from tick/
rm -rf "$tmp"
echo "ready: tick.q, tick/u.q, tick/r.q, tick/chainedtick.q, tick/sym.q -> ../sym.q, log/"
