/ exec-tca-stack : benchmark & TCA library  (.b namespace, pure functions)
/ Every function takes the tables it needs explicitly, so the same code runs
/ live inside the CEP and in batch over a replayed HDB day.
/ Convention: bps are SIGNED so that POSITIVE = favourable to the order
/ (a buy that paid below the benchmark, a sell that sold above it).

\d .b
buyorsell:{?[x="B"; 1f; -1f]};            / +1 buy, -1 sell (not signum: side is a char)
/ A fill and its tape print are stamped by the tickerplant a moment apart, so a
/ tape window that ends exactly on the last fill would miss that fill's own print.
tapeLag:0D00:00:00.050;

/ ── arrival price / implementation shortfall ────────────────────────────
/ arrivalMid is stamped on the parent at the moment it arrived (see engine.q).
arrival:{[parent;execs]
  f:select averageFillPrice:(sum lastPx*lastQty)%sum lastQty, filled:sum lastQty
      by parentOrderID from execs where execType="F";
  p:0!(parent lj f);
  update slipBps:1e4*.b.buyorsell[side]*(arrivalMid-averageFillPrice)%arrivalMid,
         fillRate:(0^filled)%qty from p };

/ IS decomposition against an optional decision mid captured before arrival:
/ delay (decision→arrival) + execution (arrival→avg fill) + opportunity (unfilled).
/ delay = decision->arrival; execution = arrival->avg fill on the FILLED shares;
/ opportunity = the move on the UNFILLED shares, decision->end price.
shortfall:{[parent;execs;decisionMid;endPx]
  a:update decisionMid:decisionMid, endPx:endPx from arrival[parent;execs];
  update delayBps:1e4*.b.buyorsell[side]*(decisionMid-arrivalMid)%decisionMid,
         execBps :?[fillRate>0; fillRate*1e4*.b.buyorsell[side]*(arrivalMid-averageFillPrice)%decisionMid; 0f],
         oppBps  :(1-fillRate)*1e4*.b.buyorsell[side]*(arrivalMid-endPx)%decisionMid
    from a };

/ the same, one level down: each algo order against the mid when the algo got it.
/ This is the number an algo wheel scores.
algoArrival:{[algoOrd;execs]
  f:select averageFillPrice:(sum lastPx*lastQty)%sum lastQty, filled:sum lastQty
      by algoOrderID from execs where execType="F";
  a:0!(algoOrd lj f);
  update slipBps:1e4*.b.buyorsell[side]*(arrivalMid-averageFillPrice)%arrivalMid,
         fillRate:(0^filled)%qty from a };

/ per algo: cost, completeness and stability side by side, never one alone.
/ The algo-level twin of the venue scorecard: this one feeds the wheel, that one
/ the router. stdErr is the uncertainty of avgSlipBps; comparing two algos is the
/ wheel's job, not this table's.
algoScorecard:{[aa] 0!select algoOrders:count i, shares:sum 0^filled,
    avgFillRate:avg fillRate, medFillRate:med fillRate,
    avgSlipBps:avg slipBps, medSlipBps:med slipBps where not null slipBps,
    sharesWtdBps:(0^filled) wavg slipBps, slipStd:dev slipBps where not null slipBps,
    stdErr:(dev slipBps where not null slipBps)%sqrt sum not null slipBps
    by algo from aa };

/ ── VWAP (interval) ──────────────────────────────────────────────────────
/ the tape over each parent's own active window [first fill; last fill].
ivwap:{[parent;trade;execs]
  sp:0!select startTime:min time, endTime:max time, averageFillPrice:(sum lastPx*lastQty)%sum lastQty
       by parentOrderID, sym, side from execs where execType="F";
  / `where sym=sy` uses the g# index on sym; a vector scan of the column would not
  f:{[t;sy;s;e] v:select px,size from t where sym=sy, time within (s;e+.b.tapeLag);
       $[count v; (v`size) wavg v`px; 0n]}[trade];
  vw:f'[sp`sym; sp`startTime; sp`endTime];
  update vwap:vw, slipBps:1e4*.b.buyorsell[side]*(vw-averageFillPrice)%vw from sp };

/ the same VWAP from running sums: two aj's instead of one tape scan per parent.
/ Keep cumulative notional and volume per sym; the VWAP over [s;e] is the change
/ in both between e and the instant before s (Earley, KX white paper).
ivwapFast:{[trade;execs]
  sp:0!select startTime:min time, endTime:max time, averageFillPrice:(sum lastPx*lastQty)%sum lastQty
       by parentOrderID, sym, side from execs where execType="F";
  c:update cn:sums px*size, cv:sums size by sym from select time,sym,px,size from trade;
  c:select sym,time,cn,cv from c;
  e:aj[`sym`time; select sym, time:endTime+.b.tapeLag from sp; c];       / sums at the end
  s:aj[`sym`time; select sym, time:startTime-0D00:00:00.000000001 from sp; c];  / just before start
  vw:((0^e`cn)-0^s`cn)%(0^e`cv)-0^s`cv;                                    / 0%0 -> 0n: no prints
  update vwap:vw, slipBps:1e4*.b.buyorsell[side]*(vw-averageFillPrice)%vw from sp };

/ TWAP: mean mid over the same window (equal 100ms spacing ≈ time-weighted).
twap:{[quote;sy;s;e] q:select bid,ask from quote where sym=sy, time within (s;e);
  $[count q; avg 0.5*q[`bid]+q`ask; 0n] };

/ ── markouts ─────────────────────────────────────────────────────────────
/ one as-of join per horizon against a SHIFTED fill time — positive = our way.
markout:{[execs;quote;horizons]
  f:select time,sym,side,lastPx,lastQty,venue,liq from execs where execType="F";
  / join only bid/ask: quote has its own `venue` column, which would otherwise
  / overwrite the fill's venue and collapse the scorecard onto one venue.
  mo:{[quote;f;h] m:aj[`sym`time; update time:time+h from f; select time,sym,bid,ask from quote];
      update horizon:h, bps:1e4*.b.buyorsell[side]*((0.5*bid+ask)-lastPx)%lastPx from m
     }[quote;f];
  raze mo each horizons };

/ the venue scorecard — the table the routing table should be reading.
scorecard:{[mk] 0!select numberOfFills:count i, shares:sum lastQty, averageBps:avg bps
  by venue, horizon from mk };

/ ── effective / realised spread, and price impact ───────────────────────
/ effective = cost vs mid AT the fill; realised = cost vs mid h later;
/ impact = effective - realised (how far the mid moved our way and stayed).
/ NOTE: these three follow the standard microstructure convention, POSITIVE = COST
/ PAID — the opposite of arrival/markout above, where positive = favourable.
spreads:{[execs;quote;h]
  f:select time,sym,side,lastPx,lastQty,venue from execs where execType="F";
  qt:select time,sym,bid,ask from quote;          / only what the join needs
  a0:aj[`sym`time; f; qt];
  ah:aj[`sym`time; update time:time+h from f; qt];
  mid0:0.5*a0[`bid]+a0`ask;                      / bracket form: `bid+`ask would be a type error
  midh:0.5*ah[`bid]+ah`ask;
  r:update effectiveBps :1e4*2*.b.buyorsell[side]*(lastPx-mid0)%lastPx,
           realisedBps:1e4*2*.b.buyorsell[side]*(lastPx-midh)%lastPx from f;
  update impact:effectiveBps-realisedBps from r };

/ ── order-flow imbalance ────────────────────────────────────────────────
/ signed net change in depth at the touch over a trailing window.
/ Delta PER VENUE first: quote interleaves venues, so a plain `deltas bsize`
/ grouped by sym alone differences one venue's size against another's. `1_`
/ drops the leading element, which is the level itself, not a change.
ofi:{[quote;w]
  v:select db:sum 1_deltas bsize, da:sum 1_deltas asize
    by sym, venue from quote where time>(max time)-w;
  0!select ofi:(sum db)-sum da by sym from v };

/ ── impact model & schedule ──────────────────────────────────────────────
/ realised participation: executed shares / tape volume in the parent's window.
participation:{[parent;trade;execs]
  sp:0!select startTime:min time, endTime:max time, executedQty:sum lastQty by parentOrderID, sym from execs where execType="F";
  f:{[t;sy;s;e] exec sum size from t where sym=sy, time within (s;e+.b.tapeLag)}[trade];
  update pov:executedQty%0f+f'[sp`sym;sp`startTime;sp`endTime] from sp };

/ square-root pre-trade cost estimate (bps): cost = C · sigma · sqrt(Q/ADV).
pretrade:{[C;sigma;Q;ADV] 1e4*C*sigma*sqrt Q%0f+ADV };

/ closing price per sym — the 'close' benchmark.
closePx:{[trade] 0!select closePx:last px by sym from trade };

/ intraday volume curve (U-shape) in 5-minute buckets.
volcurve:{[trade] 0!select vol:sum size by bar:0D00:05:00 xbar time from trade };
\d .
