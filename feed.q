/ exec-tca-stack : synthetic feed  (market data tape + order/execution flow)
/ usage:  q feed.q [:host]:5010
/ Publishes to the main tickerplant WITHOUT a time column — the TP stamps
/ `time` (timespan) on receipt, per the kdb-tick contract.

\l sym.q
TP:`$":",$[count .z.x; first .z.x; ":5010"];
h:neg hopen TP;                              / async handle to the tickerplant
pub:{h(`.u.upd;x;y)};                        / feeds call .u.upd on the TP; y = columns, no time

/ all top-level (no namespace): KDB-X does not fall back to root for reads
n:count uni;
mid:value refPx;                             / live mid per sym, aligned to uni
prevMid:mid;                                 / the mid one tick ago: resting orders fill on the move
fastD:n#0f; slowD:n#0f;                       / venue after-effects, two speeds (bps pools)
impD:n#0f;                                    / our own market impact, decaying (bps)
vol:0.00001+0.000004*til n;                   / per-step volatility per sym (~0.1-0.4 bps)
/ After each fill a venue moves the mid AGAINST the trader by these amounts (bps):
/ fast = within a second (someone was quicker), slow = over about a minute
/ (someone knew more). Centred over the lit venues, so that an algo's own later
/ fills are not helped or hurt by its own routing; the dark venues leak nothing.
toxF:venues!(-0.4 -0.4 -0.4 0.8 0.0 0.0);    / EDGX: damage inside the first second
toxS:venues!(-0.5 -0.5 0.45 0.05 0.0 0.0);   / BATS: damage that keeps arriving
alpha:1.5;                                    / the decision's signal: bps the price drifts the order's way, on average
impK:0.02; impDecay:0.85;                     / impact per 100 shares, and how fast it partly fades per tick
pool:`ARCA`NSDQ`BATS`EDGX`EDGX`BATS`MLIT`INTL; / default router mix (lit-heavy, some dark/house)
litPool:`ARCA`NSDQ`BATS`EDGX`EDGX`BATS;        / sweep the lit book only
darkPool:`MLIT`MLIT`INTL;                      / midpoint and house only
/ the four broker algos the wheel chooses between, and how each one behaves
/   pTrade   share of ticks it sends a child     sMin,sRange  child size, in lots
/   pPassive share of lit children that rest      route        which venue pool
algoParams:([algo:`VWAP`POV`ARRIVAL`DARK]
  pTrade:0.5 0.8 1.0 0.25; sMin:1 1 3 2; sRange:3 4 6 5;
  pPassive:0.45 0.3 0.0 0.0; route:`pool`pool`lit`dark);
algoNames:exec algo from 0!algoParams;
lot:100; seq:0; nTick:0;                       / nTick counts timer ticks (100ms each)
nid:{seq+:1; `$x,string seq};                 / monotonic id with a prefix
rnd:{-1f+2f*x?1f};                            / x draws, uniform on (-1,1)

/ ── market data ─────────────────────────────────────────────────────────
/ Each fill adds its venue's toxicity (bps) to the two drift pools. Those pools
/ decay, so a pool of D bps must be released as D*(1-decay) per step — otherwise
/ the same displacement is re-applied every tick and the price runs away.
/ NOTE the `::` — inside a lambda a plain `x:` binds a LOCAL, so the clamp was
/ silently doing nothing. (`x*:` and `x[i]+:` DO amend the global; `x:` does not.)
/ Decay and clamp are folded into one global assignment each.
mdStep:{ prevMid::mid;
  fastD::(-12f)|12f&0.55*fastD;               / fast decays sub-second, then clamp
  slowD::(-12f)|12f&0.99*slowD;               / slow decays over ~7s, then clamp
  rev:impD*impDecay-1; impD+:rev;             / impact fades: the price gives some back
  drift:1e-4*(0.45*fastD)+(0.01*slowD)+rev;   / per-step share of the move
  pull:0.0005*(value refPx)-mid;              / gentle pull to the anchor px
  mid+:pull+(mid*vol*rnd n)+(mid*drift); };

pushQuotes:{ nv:count lit; r:n*nv;
  sy:raze nv#'uni; vv:r#lit; m:raze nv#'mid;  / sym-major rows, lit cycled within each sym
  hs:0.01*1+r?3; vj:0.005*rnd r;              / 1–3c half-spread, small per-venue offset
  pub[`quote;(sy; vv; m-hs+vj; m+hs+vj; lot*1+r?15; lot*1+r?15)]; };

pushTape:{ k:10+rand 20; ix:k?n;              / 10–29 background prints near the touch
  pub[`trade;(uni ix; pool k?count pool; (mid ix)+0.005*rnd k; lot*1+k?10)]; };

/ ── order / execution flow ──────────────────────────────────────────────
/ parent (the PM's order) -> algo orders (one per broker algo) -> children -> fills.
/ The feed works ALGO orders; a parent is just the sum of its algo orders.
/ limitPx is null for a market order; born is the tick it arrived on.
active:([algoOrderID:`symbol$()] parentOrderID:`symbol$(); sym:`symbol$(); side:`char$();
  algo:`symbol$(); qty:`long$(); filledQty:`long$(); limitPx:`float$(); born:`long$());

spawnParent:{ if[0.08<first 1?1f; :()];       / ~8% of ticks start a parent
  s:first 1?n; sd:$[0.5>first 1?1f;"B";"S"]; sg:$[sd="B";1f;-1f];
  q:lot*10*1+first 1?40; p:nid"P";
  / 30% of parents carry a limit 1-3 bps through the arrival mid; the rest are market
  isLim:0.3>first 1?1f; ot:$[isLim;"L";"M"];
  lim:$[isLim; (mid s)*1+1e-4*sg*1+first 1?2f; 0n];
  / a parent carries a small directional signal: the price tends to drift its way
  / over the next half minute. That is decision quality, separate from execution.
  @[`slowD; s; +; sg*alpha*first 1?2f];
  / the parent, as the OMS records it: no algo yet, no child
  pub[`ord;(enlist uni s; enlist p; enlist `; enlist `; enlist `; enlist sd; enlist ot;
            enlist q; enlist lim; enlist "0"; enlist `; enlist `NEW)];
  / the trader hands it to one or two DIFFERENT broker algos, picked at random.
  / Random assignment reduces selection bias and gives each algo a comparable
  / sample of flow; enough of it is what makes the comparison meaningful.
  q1:lot*floor 0.6*q%lot;                      / a 60/40 split, in whole lots
  qs:$[0.6>first 1?1f; enlist q; (q1; q-q1)];
  k:count qs; ids:nid'[k#"A"]; al:algoNames neg[k]?count algoNames;   / neg: deal, no repeats
  `active upsert ([] algoOrderID:ids; parentOrderID:k#p; sym:k#uni s; side:k#sd; algo:al;
    qty:qs; filledQty:k#0; limitPx:k#lim; born:k#nTick);
  pub[`ord;(k#uni s; k#p; ids; al; k#`; k#sd; k#ot; qs; k#lim; k#"0"; k#`SOR; k#`NEW)]; };

workOrders:{ if[0=count active; :()];
  a:0!active;
  / a limited order only trades while the touch is inside its limit
  m0:mid uni?a`sym; isBuy:(a`side)="B";
  a:a where (null a`limitPx) | ?[isBuy; (m0+0.01)<=a`limitPx; (m0-0.01)>=a`limitPx];
  a:a lj algoParams;                            / each algo order picks up its algo's behaviour
  a:a where (count[a]?1f)<a`pTrade;             / and only trades on its share of ticks
  if[0=count a; :()];
  c:count a; si:uni?a`sym; sg:?[(a`side)="B"; 1f; -1f]; r:a`route;
  vn:?[r=`lit; litPool c?count litPool; ?[r=`dark; darkPool c?count darkPool; pool c?count pool]];
  passive:(vn in lit) & (c?1f)<a`pPassive;
  / A resting order fills mainly when the market comes to it: here a resting buy is
  / hit as the price falls or holds, never as it rises. That makes adverse selection
  / possible, where filling every resting order by construction would hide it; the
  / rebate is what a venue pays you to accept it. (Real queues also fill through
  / queue advance and contra flow; this feed keeps only the price-driven part.)
  k:where not passive & 0<sg*(mid si)-prevMid si;
  if[0=count k; :()];
  a:a k; vn:vn k; passive:passive k; si:si k; sg:sg k; c:count k;
  slice:(a[`qty]-a`filledQty) & lot*a[`sMin]+floor a[`sRange]*c?1f;   / capped at remaining
  takePx:(mid si)+0.01*sg;                      / take: pay the far touch
  makePx:(prevMid si)-0.01*sg;                  / make: the near touch you were resting on
  px:?[passive; makePx; ?[vn in lit; takePx; mid si]];   / dark / house fill at the mid
  liq:?[vn in lit; ?[passive; "A"; "R"]; ?[vn=house; "I"; "M"]];
  / R removed lit, A added lit, I internalised, M dark midpoint.
  / functional amend: accumulates when two orders hit the same sym in one tick
  @[`fastD; si; +; neg sg*toxF vn];             / the venue's after-effect, against the trader
  @[`slowD; si; +; neg sg*toxS vn];
  imp:sg*impK*slice%lot;                        / our own impact: moves the price now, then partly fades
  @[`impD; si; +; imp]; @[`mid; si; *; 1+1e-4*imp];
  cum:a[`filledQty]+slice; lv:a[`qty]-cum;      / per algo order, mirroring FIX CumQty / LeavesQty
  pub[`execs;(a`sym; a`parentOrderID; a`algoOrderID; a`algo; nid'[c#"C"]; a`side; c#"F";
             px; slice; lv; cum; vn; liq)];
  pub[`trade;(a`sym; vn; px; slice)];           / our own fills print on the tape too
  `active upsert (cols active)#update filledQty:cum from a;   / write progress back by key
  if[count fin:a[`algoOrderID] where lv<=0; delete from `active where algoOrderID in fin]; };

/ an algo order that has not finished within 60s is abandoned: its unfilled
/ remainder is what the opportunity-cost benchmark measures.
expire:{ delete from `active where born<nTick-600; };

.z.ts:{ nTick+:1; mdStep[]; pushQuotes[]; pushTape[]; spawnParent[]; workOrders[]; expire[] };
system"t 100";                                 / drive the feed every 100ms
-1"feed → ",string[TP]," : ",string[n]," names, t=100ms. \\t 0 to pause.";
