# exec-tca-stack

A small live kdb+/q tick stack for execution benchmarks and transaction cost
analysis (TCA): a synthetic equities feed, a tickerplant, a chained tickerplant,
and a TCA engine that computes arrival slippage, VWAP, markouts, spreads,
order-flow imbalance and more, live or from a replayed log.

It is the code behind the document [Anatomy of a Fill](https://rohanshiloh.github.io/exec-tca-stack/),
which explains every benchmark with diagrams and labs. Developed on KDB-X 5.0.

## Setup

```sh
git clone https://github.com/rohanshiloh/exec-tca-stack
cd exec-tca-stack
./setup.sh
```

`setup.sh` fetches the KX reference tickerplant (`tick.q`, `tick/u.q`, `tick/r.q`,
`tick/chainedtick.q`) from KX's own repositories, which this repository does not
redistribute, links the schema into `tick/`, and creates `log/`.

## Run

One process per terminal, from the repository root:

```sh
q tick.q sym ./log -p 5010            # tickerplant
q tick/r.q :5010 -p 5011              # RDB
q sym.q -p 5012                       # HDB
q tick/chainedtick.q :5010 -p 5013    # chained tickerplant
q tca.q :5013 -p 5014                 # TCA engine
q feed.q :5010                        # synthetic feed
q lab.q                               # control prompt
```

Or, in Warp: `cp warp.yaml ~/.warp/launch_configurations/exec-tca-stack.yaml` and
open the launch configuration. Its paths assume `~/Code/exec-tca-stack`.

In the TCA process try `arrival[]`, `scorecard[]`, `spreads[]`, `ofi[]`, `vwap[]`,
`pov[]`, and the beyond-vanilla set `robust[]`, `fees[]`, `cohorts[]`,
`limited[]`, `pwp[]`, `bands[]`, `context[]`, `peers[]`.
`\l dump.q` then `tcaDump[]` writes them all to `tcaData.txt`.

## Files

| File | Role |
|---|---|
| `sym.q` | schema and reference data |
| `feed.q` | synthetic market data and order/execution flow |
| `engine.q` | parent-order state, event handlers, benchmark wrappers |
| `bench.q` | core benchmark library (`.b` namespace) |
| `beyond.q` | beyond-vanilla benchmarks |
| `tca.q` | live TCA engine, subscribed to the chained tickerplant |
| `replay.q` | the same engine over a tickerplant log |
| `rescue.q` | recover a truncated tickerplant log |
| `lab.q` | control-prompt helpers |
| `dump.q` | write diagnostics to `tcaData.txt` |
| `warp.yaml` | Warp launch configuration |

The feed is a simulation: prices, venues and fills are synthetic, and the
reference mid is one venue's quote rather than a consolidated NBBO.
