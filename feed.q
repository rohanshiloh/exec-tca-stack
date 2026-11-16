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
fastD:n#0f; slowD:n#0f;                       / adverse-selection drift, two speeds
vol:0.00001+0.000004*til n;                   / per-step volatility per sym (~0.1-0.4 bps)
/ Post-fill kick per venue, in bps AGAINST the trader (negative = the mid moves
/ with the trade). Split in two speeds: fast = gone within a second (latency),
/ slow = arrives over about a minute (information). The values are centred so
/ the average over the venue pool is ~0: a parent's own later fills then do not
/ swamp the venue signal, and the scorecard can tell the venues apart.
toxF:venues!(-0.35 -0.45 -0.35 0.77 -0.6 -0.4);  / EDGX: damage inside the first second
toxS:venues!(-0.25 -0.25 0.45 0.2 -0.5 -0.3);    / BATS: damage that keeps arriving
passiveKick:0.4;                               / extra fast kick when a resting order is hit
pool:`ARCA`NSDQ`BATS`EDGX`EDGX`BATS`MLIT`INTL; / SOR venue mix (lit-heavy, some dark/house)
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
mdStep:{ fastD::(-12f)|12f&0.55*fastD;        / fast decays sub-second, then clamp
  slowD::(-12f)|12f&0.99*slowD;               / slow decays over ~7s, then clamp
  drift:1e-4*(0.45*fastD)+(0.01*slowD);                   / per-step share of the move
  pull:0.0005*(value refPx)-mid;                          / gentle pull to the anchor px
  mid+:pull+(mid*vol*rnd n)+(mid*drift); };

pushQuotes:{ nv:count lit; r:n*nv;
  sy:raze nv#'uni; vv:r#lit; m:raze nv#'mid;  / sym-major rows, lit cycled within each sym
  hs:0.01*1+r?3; vj:0.005*rnd r;              / 1–3c half-spread, small per-venue offset
  pub[`quote;(sy; vv; m-hs+vj; m+hs+vj; lot*1+r?15; lot*1+r?15)]; };

pushTape:{ k:10+rand 20; ix:k?n;              / 10–29 background prints near the touch
  pub[`trade;(uni ix; pool k?count pool; (mid ix)+0.005*rnd k; lot*1+k?10)]; };

/ ── order / execution flow ──────────────────────────────────────────────
/ limitPx is null for a market parent; born is the tick it arrived on.
active:([parentOrderID:`symbol$()] sym:`symbol$(); side:`char$(); qty:`long$(); filledQty:`long$();
  limitPx:`float$(); born:`long$());

spawnParent:{ if[0.08<first 1?1f; :()];       / ~8% of ticks start a parent
  s:first 1?n; sd:$[0.5>first 1?1f;"B";"S"]; q:lot*10*1+first 1?40; p:nid"P";
  / 30% of parents carry a limit 1-3 bps through the arrival mid; the rest are market
  isLim:0.3>first 1?1f;
  lim:$[isLim; (mid s)*1+1e-4*$[sd="B";1f;-1f]*1+first 1?2f; 0n];
  `active upsert (p; uni s; sd; q; 0; lim; nTick);
  pub[`ord;(enlist uni s; enlist p; enlist p; enlist sd; enlist $[isLim;"L";"M"];
            enlist q; enlist lim; enlist "0"; enlist `SOR; enlist `NEW)]; };

workOrders:{ if[0=count active; :()];
  a:0!active;
  / a limited parent only trades while the touch is inside its limit
  m0:mid uni?a`sym; isBuy:(a`side)="B";
  a:a where (null a`limitPx) | ?[isBuy; (m0+0.01)<=a`limitPx; (m0-0.01)>=a`limitPx];
  if[0=count a; :()];
  c:count a; rem:a[`qty]-a`filledQty;
  slice:rem & lot*1+c?5;                       / child slice, capped at remaining
  si:uni?a`sym; buy:a[`side]="B"; vn:pool c?count pool;
  / 40% of lit children REST at the near touch instead of crossing to the far one.
  passive:(vn in lit) & 0.40>c?1f;
  takePx:(mid si)+?[buy; 0.01; -0.01];          / take: pay the far touch
  makePx:(mid si)-?[buy; 0.01; -0.01];          / make: earn the near touch
  px:?[vn in lit; ?[passive; makePx; takePx]; mid si];      / dark / house fill at the mid
  liq:?[vn in lit; ?[passive; "A"; "R"]; ?[vn=house; "I"; "M"]];
  / R removed lit, A added lit, I internalised, M dark midpoint.
  / `push` models NET post-fill adverse drift (what markouts measure); it does not
  / separate your own impact from being picked off on a passive fill.
  / A RESTING fill is adversely selected harder: you were filled because the other
  / side wanted out just before the move. That is what the rebate is paying for.
  push:?[buy; -1f; 1f];                         / a buy on a toxic venue drifts the mid down
  / functional amend: accumulates when two parents hit the same sym in one tick
  @[`fastD; si; +; push*(toxF vn)+passiveKick*passive];
  @[`slowD; si; +; push*toxS vn];
  cum:a[`filledQty]+slice; lv:a[`qty]-cum;
  pub[`execs;(a`sym; a`parentOrderID; nid'[c#"C"]; a`side; c#"F";
             px; slice; lv; cum; vn; liq)];
  pub[`trade;(a`sym; vn; px; slice)];           / our own fills print on the tape too
  `active upsert update filledQty:cum from a;       / write progress back by key
  if[count fin:a[`parentOrderID] where lv<=0; delete from `active where parentOrderID in fin]; };

/ a parent that has not finished within 60s is abandoned: its unfilled remainder
/ is what the opportunity-cost benchmark measures.
expire:{ delete from `active where born<nTick-600; };

.z.ts:{ nTick+:1; mdStep[]; pushQuotes[]; pushTape[]; spawnParent[]; workOrders[]; expire[] };
system"t 100";                                 / drive the feed every 100ms
-1"feed → ",string[TP]," : ",string[n]," names, t=100ms. \\t 0 to pause.";
