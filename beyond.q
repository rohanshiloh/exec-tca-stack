/ exec-tca-stack : beyond-vanilla TCA  (the F labs; extends the .b namespace)
/ Loaded by engine.q after bench.q. Defined from the root with explicit .b.
/ names, because KDB-X does not fall back to the root for reads made inside
/ a namespace, and these functions read root reference data (venues).

/ ── F1 robust arrival ────────────────────────────────────────────────────
/ median mid over [arrivalTime; arrivalTime+w], not a single snapshot
.b.robustArrival:{[parent;quote;w]
  g:{[q;sy;t;w] m:q where (q`sym)=sy; m@:where m[`time] within (t;t+w);
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
  v:trade where (trade`sym)=sy; v@:where v[`time] within (startTime;endTime);
  v@:where $[side="B"; v[`px]<=lim; v[`px]>=lim];   / in-limit only
  $[count v; (v`size) wavg v`px; 0n] };

/ one row per parent: marketable or limited, with its limit
.b.cohort:{[ord]
  update cohort:?[ordType="M";`marketable;`limited] from
    select ordType:last ordType, limitPx:last limitPx by parentOrderID from ord where msgType=`NEW };

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
  mv:{[q;sy;startTime;endTime] b:q where (q`sym)=sy; m:0.5*b[`bid]+b`ask;
       m0:last m where b[`time]<=startTime; m1:last m where b[`time]<=endTime;
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
