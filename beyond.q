/ exec-tca-stack : beyond-vanilla TCA  (the F labs; extends the .b namespace)
/ Loaded by engine.q after bench.q. Defined from the root with explicit .b.
/ names, because KDB-X does not fall back to the root for reads made inside
/ a namespace, and these functions read root reference data (venues).

/ ── F1 robust arrival ────────────────────────────────────────────────────
/ median mid over [arrivalTime; arrivalTime+w], not a single snapshot
.b.robustArrival:{[parent;quote;w]
  g:{[q;sy;t;w] m:select bid,ask from q where sym=sy, time within (t;t+w);
       $[count m; med 0.5*m[`bid]+m`ask; 0n]}[quote];
  p:0!parent;
  update arrivalMidRobust:g'[p`sym;p`arrivalTime;w] from p };

/ ── F2 fee-aware cost ────────────────────────────────────────────────────
/ fees in bps of notional; positive = you pay, negative = you are paid
.b.takerFee:venues!0.30 0.30 0.29 0.30 0.10 0.0;   / MLIT 0.10, INTL free
.b.makerReb:venues!0.20 0.20 0.25 0.18 0.0 0.0;    / no rebate off-exchange
/ spreadBps = what the fill paid against the mid at the fill (negative = earned)
/ feeBps    = taker fee, maker rebate, or dark access fee
/ allInBps  = the two together: the cost of the fill before any markout
.b.feeAware:{[execs;quote]
  f:select time,sym,side,lastPx,lastQty,venue,liq from execs where execType="F";
  a0:aj[`sym`time; f; select time,sym,bid,ask from quote];
  mid0:0.5*a0[`bid]+a0`ask;
  lq:f`liq; vn:f`venue;
  fee:?[lq="R"; .b.takerFee vn;                     / removed lit: pay
       ?[lq="A"; neg .b.makerReb vn;                / added lit: earn
        ?[lq="M"; .b.takerFee vn; 0f]]];            / dark: access fee; "I" free
  update spreadBps:1e4*.b.buyorsell[side]*(lastPx-mid0)%lastPx, feeBps:fee from f };

/ ── F3 marketable vs limited ─────────────────────────────────────────────
/ VWAP over only the prints a limit order could have traded against
.b.limVwap:{[trade;sy;startTime;endTime;side;lim]
  v:select px,size from trade where sym=sy, time within (startTime;endTime);
  v@:where $[side="B"; v[`px]<=lim; v[`px]>=lim];   / in-limit only
  $[count v; (v`size) wavg v`px; 0n] };

/ one row per parent: marketable or limited, with its limit
.b.cohort:{[ord]
  update cohort:?[ordType="M";`marketable;`limited] from
    select ordType:last ordType, limitPx:last limitPx by parentOrderID from ord where msgType=`NEW, null algoOrderID };

/ ── F4 PWP and the achievable range ──────────────────────────────────────
/ size-weighted average of the first Q shares of a price-sorted tape
.b.takeQ:{[v;Q] cum:sums v`size; k:1+first where cum>=Q;
  w:k#v`size; w[k-1]-:(sum w)-Q;                    / trim the last lot to hit Q exactly
  w wavg k#v`px };

/ PWP plus the cheapest and dearest average an order of Q shares could have got
.b.pwpRange:{[trade;tenor;sy;startTime;Q]
  v:select px,size from trade where sym=sy, time>=startTime;
  k:1+first where (sums v`size)>=Q%tenor;           / first print that crosses the window
  v:((count v)^k)#v;                                / the volume-time window
  if[Q>sum v`size; :`pwp`cheapest`dearest!3#0n];    / not enough tape left
  `pwp`cheapest`dearest!(
    (v`size) wavg v`px;
    .b.takeQ[`px xasc v; Q];
    .b.takeQ[`px xdesc v; Q]) };

/ per parent: where the average fill landed in that range (0 = best, 1 = worst)
.b.pwpTable:{[parent;trade;execs;tenor]
  a:select parentOrderID,sym,side,arrivalTime,filled,averageFillPrice
      from .b.arrival[parent;execs] where filled>0;
  r:.b.pwpRange[trade;tenor]'[a`sym;a`arrivalTime;a`filled];
  t:a,'r;
  update landed:?[side="B"; (averageFillPrice-cheapest)%dearest-cheapest;
                            (dearest-averageFillPrice)%dearest-cheapest] from t };

/ ── F5 point-in-time bands ───────────────────────────────────────────────
/ the same fills marked against the quote 5s early, 1s early, on time, 1s and 5s late
.b.pitBands:{[execs;quote]
  f:select time,sym,side,lastPx from execs where execType="F";
  qt:select time,sym,bid,ask from quote;
  g:{[qt;f;dt] m:aj[`sym`time; update time:time+dt from f; qt];
       avg 1e4*.b.buyorsell[f`side]*((0.5*m[`bid]+m`ask)-f`lastPx)%f`lastPx}[qt;f];
  ([] dt:`$("-5s";"-1s";"t";"+1s";"+5s");
      bps:g each (-5 -1 0 1 5)*0D00:00:01) };

/ ── F6 execution vs market ───────────────────────────────────────────────
/ mktBps  = what the market's own move over the order's window did to you
/ execBps = slippage with that move taken out
.b.contextNorm:{[parent;execs;quote]
  a:.b.arrival[parent;execs];
  w:select startTime:min time, endTime:max time by parentOrderID
      from execs where execType="F";
  a:a lj w;
  mv:{[q;sy;startTime;endTime]
       m0:exec last 0.5*bid+ask from q where sym=sy, time<=startTime;
       m1:exec last 0.5*bid+ask from q where sym=sy, time<=endTime;
       1e4*(m1-m0)%m0}[quote];
  mk:mv'[a`sym;a`startTime;a`endTime];
  update mktBps:neg .b.buyorsell[side]*mk,
         execBps:slipBps+.b.buyorsell[side]*mk from a };

/ ── F7 percentile scoring ────────────────────────────────────────────────
/ each fill's arrival-relative cost, ranked within its side and size bucket
.b.pctScore:{[parent;execs]
  f:select parentOrderID,sym,side,lastPx,lastQty from execs where execType="F";
  f:f lj select arrivalMid by parentOrderID from parent;
  f:update szBucket:`sm`md`lg 0 300 500 bin lastQty,
           cost:1e4*.b.buyorsell[side]*(arrivalMid-lastPx)%arrivalMid from f;
  update pct:100*(rank cost)%count i by side, szBucket from f };

/ ── D2 outliers ──────────────────────────────────────────────────────────
/ clamp each value into [lo;hi] so one busted print cannot move a mean
.b.winsor:{[x;lo;hi] lo | hi & x };

/ ── the algo wheel: fit slippage to its drivers ──────────────────────────
/ ordinary least squares, beta = (X'X)^-1 X'y ; X is a list of rows
.b.wheelFit:{[X;y] (inv flip[X] mmu X) mmu flip[X] mmu y };
/ the same, with a standard error per coefficient: (beta; se)
.b.olsFit:{[X;y] xi:inv flip[X] mmu X; b:xi mmu flip[X] mmu y;
  e:y-X mmu b; s2:(e wsum e)%count[y]-count b;
  (b; sqrt s2*xi@'til count b) };

/ the same, with standard errors that allow for orders in a cluster (here, the
/ algo orders of one parent) sharing a market: they are not independent draws.
.b.olsCluster:{[X;y;g] xi:inv flip[X] mmu X; b:xi mmu flip[X] mmu y; e:y-X mmu b;
  m:sum {[X;e;i] v:flip[X i] mmu e i; v*/:v}[X;e] each value group g;
  G:count distinct g;
  (b; sqrt (G%G-1)*(xi mmu m mmu xi)@'til count b) };

/ one row per algo order: its slippage, which algo it went to, and two controls.
/ VWAP is the base, so each flag reads "bps relative to VWAP".
.b.wheelData:{[algoOrd;execs;ord]
  a:.b.algoArrival[algoOrd;execs] lj .b.cohort ord;
  select algoOrderID, parentOrderID, algo, slipBps,
         isPOV:`float$algo=`POV, isARRIVAL:`float$algo=`ARRIVAL, isDARK:`float$algo=`DARK,
         limited:`float$cohort=`limited, sizeK:qty%10000
    from a where not null slipBps };

/ one row per parent: the slippage it earned and the conditions it faced
.b.wheelFeatures:{[parent;trade;execs;ord]
  a:.b.arrival[parent;execs] lj .b.cohort ord;
  p:`parentOrderID xkey select parentOrderID,pov from .b.participation[parent;trade;execs];
  m:select passiveShare:avg liq="A", toxicShare:avg venue=`EDGX, darkShare:avg venue in `MLIT`INTL
      by parentOrderID from execs where execType="F";
  t:(a lj p) lj m;
  select parentOrderID, slipBps, limited:`float$cohort=`limited, pov, sizeK:qty%10000,
         passiveShare, toxicShare, darkShare
    from t where not null slipBps, not null pov, pov<0w };

/ ── the paired wheel: one parent, two algos, one market ───────────────────
/ When a parent is split across two algos, both halves trade through the same
/ prices at the same time, so the difference between them has the market taken
/ out. One row per split parent: which two algos, and the differences.
.b.wheelPairs:{[algoOrd;execs]
  a:select parentOrderID, algo, slipBps, fillRate, sizeK:qty%10000
      from .b.algoArrival[algoOrd;execs] where not null slipBps;
  a:select from a where 2=(count;i) fby parentOrderID;    / both halves traded
  0!select algo1:first algo, algo2:last algo,
      dSlip:(first slipBps)-last slipBps, dFill:(first fillRate)-last fillRate,
      dSize:(first sizeK)-last sizeK
    by parentOrderID from a };

/ ── F8 live exceptions ───────────────────────────────────────────────────
/ The backtest's execution assumptions are model assumptions too. Per algo, the
/ algo orders that arrived in the last w against the session so far: flag an algo
/ only when its recent mean sits more than zMax standard errors from its baseline,
/ on at least minN orders. (The baseline includes the recent orders, so the test
/ is conservative.)
.b.exceptions:{[aa;now;w;minN;zMax]
  aa:select from aa where filled>0;
  b:select baseBps:avg slipBps, sd:dev slipBps, baseFill:avg fillRate by algo from aa;
  r:select n:count i, recentBps:avg slipBps, recentFill:avg fillRate by algo from aa where arrivalTime>now-w;
  t:update z:(recentBps-baseBps)%sd%sqrt n from 0!r lj b;
  select algo, n, recentBps, baseBps, z, recentFill, baseFill from t where n>=minN, zMax<abs z };

/ ── F9 venue mix ─────────────────────────────────────────────────────────
/ where each algo's shares actually went, and how it got them
.b.venueMix:{[execs]
  f:select from execs where execType="F";
  t:select shares:sum lastQty, nFills:count i, passive:avg liq="A" by algo, venue from f;
  update share:shares%sum shares by algo from 0!t };

/ ── F10 best-execution report: the top five venues ──────────────────────
/ In the shape of MiFID II's RTS 28 table: share of volume and of orders, and how
/ much was passive (added) vs aggressive (removed). Dark (M) and house (I) fills are
/ neither, so the two need not sum to 100.
.b.top5:{[execs]
  f:select from execs where execType="F";
  v:select vol:sum lastQty, nOrd:count distinct algoOrderID,
      pctPassive:100*avg liq="A", pctAggressive:100*avg liq="R" by venue from f;
  v:update pctVol:100*vol%sum vol, pctOrders:100*nOrd%sum nOrd from 0!v;
  5#`pctVol xdesc select venue, pctVol, pctOrders, pctPassive, pctAggressive from v };

/ F8, against a model: each algo order's realised cost against the square-root
/ estimate for its size (§Market Impact), so "expected" means what this order
/ should have cost, not what the algo cost earlier today. C is the fitted constant.
.b.vsModel:{[aa;trade;C;now;w;minN;zMax]
  sq:select adv:sum size, sigma:dev 1_deltas log px by sym from trade;
  a:select algo, sym, arrivalTime, costBps:neg slipBps, Q:filled from aa where filled>0;
  a:update expBps:C*1e4*sigma*sqrt Q%adv from a lj sq;
  r:select n:count i, costBps:avg costBps, expBps:avg expBps, sd:dev costBps-expBps
    by algo from a where arrivalTime>now-w;
  t:update z:(costBps-expBps)%sd%sqrt n from 0!r;
  select from t where n>=minN, zMax<abs z };

/ F8, per venue: recent realised spread (+ = cost) against the venue's session baseline
.b.venueExceptions:{[sp;now;w;minN;zMax]
  b:select baseBps:avg realisedBps, sd:dev realisedBps by venue from sp;
  r:select n:count i, recentBps:avg realisedBps by venue from sp where time>now-w;
  t:update z:(recentBps-baseBps)%sd%sqrt n from 0!r lj b;
  select venue, n, recentBps, baseBps, z from t where n>=minN, zMax<abs z };

/ ── F11 the audit trail ──────────────────────────────────────────────────
/ one parent, event by event: its NEW, each algo order's NEW, every fill, each with
/ the quote that prevailed at that instant, the running fill and the slippage so far
.b.audit:{[parent;ord;execs;quote;pid]
  o:select time, sym, event:?[null algoOrderID; `parentNEW; `algoNEW], algo, algoOrderID,
      venue, qty, px:limitPx from ord where parentOrderID=pid, msgType=`NEW;
  f:select time, sym, event:`fill, algo, algoOrderID, venue, qty:lastQty, px:lastPx
      from execs where parentOrderID=pid, execType="F";
  t:aj[`sym`time; `time xasc o,f; select time,sym,bid,ask from quote];
  am:first exec arrivalMid from parent where parentOrderID=pid;
  sd:first exec side from parent where parentOrderID=pid;
  update mid:0.5*bid+ask, cumQty:sums ?[event=`fill; qty; 0],
         slipBps:?[event=`fill; 1e4*.b.buyorsell[sd]*(am-px)%am; 0n] from t };

/ ── production: one-minute bars and a daily summary ─────────────────────
/ Score a large HDB from these, not from raw ticks. Built from the tape at end of
/ day (or live, minute by minute); VWAP over bars is exact: sum notional % sum volume.
.b.bars:{[trade]
  0!select open:first px, high:max px, low:min px, close:last px,
      volume:sum size, notional:sum px*size, prints:count i
    by sym, minute:0D00:01 xbar time from trade };
.b.daySummary:{[trade]
  0!select firstTime:first time, lastTime:last time, open:first px, high:max px,
      low:min px, close:last px, volume:sum size, vwap:size wavg px by sym from trade };

/ ── the cost curve ───────────────────────────────────────────────────────
/ Realised cost against order size as a share of the day's volume, in k buckets,
/ next to the square-root model with fitted constant C. Built on demand from three
/ live tables: parent (arrivalMid, stamped from quote when the order arrived), execs
/ (the fills) and trade (the tape, for ADV and sigma). Nothing is stored.
.b.costCurve:{[a;trade;C;k]
  sq:select adv:sum size, sigma:dev 1_deltas log px by sym from trade;
  a:select sym, costBps:neg slipBps, Q:filled from a where filled>0;
  a:update z:Q%adv, pred:1e4*sigma*sqrt Q%adv from a lj sq;
  0!select n:count i, pctADV:100*avg z, costBps:avg costBps, se:(dev costBps)%sqrt count i,
      modelBps:C*avg pred by bucket:k xrank z from a };

/ ── F12 the broker report ────────────────────────────────────────────────
/ The columns a retail broker's TCA page shows, per parent: price improvement
/ against the far touch at arrival, cost against the day's VWAP, how much of the
/ day's high-low range the order captured, how much of it the touch could have
/ filled at once, and how long it lived.
.b.brokerReport:{[parent;execs;quote;trade]
  p:select parentOrderID, sym, side, qty, time:arrivalTime, arrivalMid from 0!parent;
  p:aj[`sym`time; p; select time,sym,bid,ask,bsize,asize from quote];
  f:select avgPx:(sum lastPx*lastQty)%sum lastQty, filled:sum lastQty,
      liveSec:1e-9*`long$(max time)-min time by parentOrderID from execs where execType="F";
  d:select dHigh:max px, dLow:min px, dVwap:size wavg px by sym from trade;
  t:(p lj f) lj d;
  update priceImprBps:1e4*.b.buyorsell[side]*(?[side="B"; ask; bid]-avgPx)%avgPx,
         vsDayVwapBps:1e4*.b.buyorsell[side]*(dVwap-avgPx)%dVwap,
         rangeCapture:?[side="B"; (dHigh-avgPx)%dHigh-dLow; (avgPx-dLow)%dHigh-dLow],
         feasibleFill:1f&(?[side="B"; asize; bsize])%qty,
         fillRate:(0^filled)%qty from t };

/ ── four prices, four costs ──────────────────────────────────────────────
/ Perold's shortfall split at the four moments EDHEC names: the decision (P0,
/ the mid lag before the parent arrived), the desk's release to the broker (PR,
/ the parent's arrivalMid), the broker starting work (PS, the qty-weighted
/ arrivalMid of its algo orders) and the end (PT). + = favourable, all in bps of P0.
/ ops + timing are charged on every share, execution on the filled ones and
/ opportunity on the unfilled ones; the four always sum to Perold's total, isBps.
.b.shortfall4:{[parent;algoOrd;execs;quote;lag;closes]
  a:.b.arrival[parent;execs];
  d:aj[`sym`time; select sym, time:arrivalTime-lag from a; select time,sym,bid,ask from quote];
  a:update decisionMid:0.5*d[`bid]+d`ask from a;
  a:a lj select startMid:qty wavg arrivalMid by parentOrderID from algoOrd;
  a:update phi:.b.buyorsell side, endPx:closes sym from a;
  a:update opsBps:1e4*phi*(decisionMid-arrivalMid)%decisionMid,
           timingBps:1e4*phi*(arrivalMid-startMid)%decisionMid,
           execBps:?[fillRate>0; fillRate*1e4*phi*(startMid-averageFillPrice)%decisionMid; 0f],
           oppBps:(1-fillRate)*1e4*phi*(startMid-endPx)%decisionMid,
           isBps:(?[fillRate>0; fillRate*1e4*phi*(decisionMid-averageFillPrice)%decisionMid; 0f])
                 +(1-fillRate)*1e4*phi*(decisionMid-endPx)%decisionMid from a;
  select parentOrderID, sym, side, fillRate, decisionMid, arrivalMid, startMid, averageFillPrice,
    endPx, opsBps, timingBps, execBps, oppBps, isBps from a };

/ ── I-star: Kissell and Glantz's impact model ────────────────────────────
/ Instantaneous impact I = a1 * Z^a2 * sigma^a3 (bps), Z = size as % of ADV,
/ sigma = daily volatility in bps; about 95% of it is temporary and fades with
/ slower trading. pov = order size / market volume over the horizon, so the
/ participation number eta = 1 + 0.5/pov. Defaults: EDHEC's power-function fit.
.b.istar:{[Z;sigmaBps;pov]
  i:25*(Z xexp 0.38)*sigmaBps xexp 0.28;
  i*0.05+0.95%1+0.5%pov };

/ ── the rest of the yardsticks ───────────────────────────────────────────
/ The day-level benchmarks a report still shows, against each parent's average
/ fill: yesterday's close, the open, the VWAP available at arrival (open to
/ arrival, nothing after), LHOC (mean of low, high, open, close), the high-low
/ midpoint, and the close. + = favourable. Only the first three were knowable
/ when the order arrived; the rest carry hindsight.
.b.dayBench:{[parent;execs;trade;prevCl]
  a:select parentOrderID, sym, side, time:arrivalTime, averageFillPrice from .b.arrival[parent;execs] where filled>0;
  c:update cn:sums px*size, cv:sums size by sym from select time,sym,px,size from trade;
  a:aj[`sym`time; a; select sym,time,cn,cv from c];
  a:a lj select open:first px, high:max px, low:min px, close:last px by sym from trade;
  a:update phi:.b.buyorsell side, prevClose:prevCl sym, availVwap:cn%cv,
           lhoc:0.25*low+high+open+close, midHL:0.5*high+low from a;
  f:{[phi;b;p] 1e4*phi*(b-p)%b};
  select parentOrderID, sym, side, averageFillPrice,
    vsPrevClose:f[phi;prevClose;averageFillPrice], vsOpen:f[phi;open;averageFillPrice],
    vsAvailVwap:f[phi;availVwap;averageFillPrice], vsLHOC:f[phi;lhoc;averageFillPrice],
    vsMidHL:f[phi;midHL;averageFillPrice], vsClose:f[phi;close;averageFillPrice] from a };
