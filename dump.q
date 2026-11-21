/ exec-tca-stack : write TCA diagnostics to tcaData.txt
/ usage, in the TCA tab:   \l dump.q      then   tcaDump[]
/ Each query is trapped, so one failure prints its error and the rest still run.
/ After the benchmarks come the algo-wheel queries, every prompt line the labs
/ show, rescue.q and replay.q on a 5MB cut of today's tickerplant log (written
/ to /tmp), and finally checks on the other processes over handles.
tcaQueries:(
  ".z.P";
  "tables[]!count each value each tables[]";
  "exec firstFill:min time, lastFill:max time from execs";
  "count parent";
  "select fillCount:count i, shares:sum lastQty by venue, liq from execs";
  "5#arrival[]";
  "select n:count i, avgSlip:avg slipBps, medSlip:med slipBps, devSlip:dev slipBps, avgFillRate:avg fillRate by side from arrival[]";
  "scorecard[]";
  "exec horizon!averageBps by venue from scorecard[]";
  "select avgEffective:avg effectiveBps, avgRealised:avg realisedBps, avgImpact:avg impact, n:count i by venue from spreads[]";
  "ofi[]";
  "5#vwap[]";
  "select n:count i, avgSlip:avg slipBps, medSlip:med slipBps by side from vwap[]";
  "select n:count i, maxDiff:max abs vwap-vwapF from vwap[] lj 1!select parentOrderID, vwapF:vwap from vwapFast[]";
  "\\t vwap[]";
  "\\t vwapFast[]";
  "5#pov[]";
  "select n:count i, avgPov:avg pov, medPov:med pov, maxPov:max pov from pov[]";
  "closes[]";
  "select lo:min bid, hi:max bid, avgSpread:avg ask-bid by sym from quote";
  "vcurve[]";
  "5#0!parent";
  "select pctFilled:filledQty%qty, vwapFill:notional%filledQty by parentOrderID from 5#0!parent";
  "select wAvg:fillRate wavg slipBps from arrival[]";
  "select averageBps:avg bps by horizon from markouts[]";
  "select effectiveBps:avg effectiveBps, impact:avg impact by venue from spreads[]";
  "select averageBps:avg bps, n:count i by liq, horizon from markouts[]";
  "select n:count i, avgSlip:avg slipBps, avgFillRate:avg fillRate, unfinished:sum fillRate<1 by cohort from cohorts[]";
  "5#select parentOrderID,sym,arrivalMid,arrivalMidRobust from robust[]";
  "select n:count i, avgGapBps:avg abs 1e4*(arrivalMidRobust-arrivalMid)%arrivalMid, maxGapBps:max abs 1e4*(arrivalMidRobust-arrivalMid)%arrivalMid from robust[]";
  "select spreadBps:avg spreadBps, feeBps:avg feeBps, allInBps:avg spreadBps+feeBps, shares:sum lastQty by venue, liq from fees[]";
  "5#select parentOrderID,sym,side,limitPx,averageFillPrice,vwap,inLimitVwap from limited[]";
  "5#pwp[]";
  "select n:count i, avgLanded:avg landed, medLanded:med landed by side from pwp[]";
  "bands[]";
  "5#select parentOrderID,sym,side,slipBps,mktBps,execBps from context[]";
  "select n:count i, avgSlip:avg slipBps, avgMkt:avg mktBps, avgExec:avg execBps, devSlip:dev slipBps, devExec:dev execBps from context[]";
  "5#peers[]";
  "select n:count i, avgCost:avg cost, medCost:med cost by side, szBucket from peers[]";
  "5#.b.wheelFeatures[parent;trade;execs;ord]";
  "select algoOrders:count i, parents:count distinct parentOrderID by algo from algoOrd";
  "5#algoArrival[]";
  "algoScorecard[]";
  "wheel[]";
  "count .b.wheelPairs[algoOrd;execs]";
  "5#.b.wheelPairs[algoOrd;execs]";
  "wheelPaired[]";
  ".b.exceptions[algoArrival[]; max execs`time; 0D00:02; 0D00:01; 5; 0f]";
  "exceptions[]";
  "count alerts";
  "alerts";
  "venueAlerts";
  "-5#alerts";
  "select from venueMix[] where algo in `VWAP`DARK";
  "top5[]";
  "count venueAlerts";
  ".b.venueExceptions[spreads[]; max execs`time; 0D00:02; 0D00:00:10; 5; 0f]";
  "pid:first exec parentOrderID from parent where filledQty>0";
  "12#audit pid";
  "5#bars[]";
  "daySummary[]";
  "select sym, maxDiff:abs vwap-bv from daySummary[] lj select bv:(sum notional)%sum volume by sym from bars[]";
  "drivers[]";
  "select n:count i, avgPassive:avg liq=\"A\", avgDark:avg liq in \"MI\" by algo from execs";
  "5#select tot:distinct cumQty+leaves by algoOrderID from execs";
  "count select from execs where 1<({count distinct x};cumQty+leaves) fby algoOrderID";
  "5#(select aq:first qty by algoOrderID from algoOrd) lj select cum:last cumQty by algoOrderID from execs where execType=\"F\"";
  "(count execs; count select from execs where i=(first;i) fby childOrderID)";
  "select parentOrderID,sym,side,fillRate,slipBps from 5#arrival[]";
  "5#.b.shortfall[parent;execs; exec arrivalMid from 0!parent; (exec sym!closePx from closes[]) exec sym from 0!parent]";
  ".b.twap[quote;`NVDA; min quote`time; max quote`time]";
  ".b.closePx[trade]";
  ".b.pretrade[0.5; 0.018; 200000; 4000000]";
  "sq:select adv:sum size, sigma:dev 1_deltas log px by sym from trade";
  "a:select parentOrderID,sym,costBps:neg slipBps,Q:filled from arrival[] where filled>0";
  "a:update pred:1e4*sigma*sqrt Q%adv from a lj sq";
  "fitC:(sum a[`pred]*a`costBps)%sum a[`pred]*a`pred";
  "fitC";
  "select n:count i, costBps:avg costBps, modelBps:fitC*avg pred by sizeBucket:5 xrank Q from a";
  "vsModel fitC";
  "costCurve fitC";
  "5#shortfall4[]";
  "select n:count i, ops:avg opsBps, timing:avg timingBps, execution:avg execBps, opp:avg oppBps, total:avg isBps, maxGap:max abs isBps-opsBps+timingBps+execBps+oppBps from shortfall4[]";
  ".b.istar[10f;200f;100000%950000]";
  "5#dayBench[]";
  "select n:count i, prevClose:avg vsPrevClose, open:avg vsOpen, availVwap:avg vsAvailVwap, lhoc:avg vsLHOC, midHL:avg vsMidHL, close:avg vsClose by side from dayBench[]";
  "5#brokerReport[]";
  "select n:count i, priceImpr:avg priceImprBps, vsDayVwap:avg vsDayVwapBps, range:avg rangeCapture, feasible:avg feasibleFill by liveBucket:5 xrank liveSec from brokerReport[] where filled>0";
  "select n:count i, better:avg slipBps>0, worse:avg slipBps<0, avgSlip:avg slipBps by side from arrival[] where filled>0";
  "a:select parentOrderID,sym,side,qty,fillRate,slipBps from arrival[] where filled>0";
  "(5#`slipBps xasc a),5#`slipBps xdesc a";
  ".b.vsModel[algoArrival[]; trade; fitC; max execs`time; 0D00:05; 20; 0f]";
  "select averageBps:avg bps by venue from markouts[] where horizon=0D00:01:00";
  "select averageBps:avg bps, medBps:med bps, clampedBps:avg .b.winsor[bps;-25f;25f], n:count i by venue from markouts[]";
  "\\t do[20; scorecard[]]";
  "tcaLog[]";
  "{f:hsym `$tcaLog[]; (hsym `$\"/tmp/exec-tca-cut.log\") 1: read1 (f; 0; 5000000&hcount f)}[]";
  "system \"sh -c 'q rescue.q /tmp/exec-tca-cut.log -q </dev/null 2>&1; true'\"";
  "system \"sh -c 'q replay.q /tmp/exec-tca-cut.log -q </dev/null 2>&1; true'\"";
  "rq[5010;\"`date`messages`log!(.u.d;.u.i;.u.L)\"]";
  "rq[5010;\"count each .u.w\"]";
  "rq[5010;\"sum each .z.W\"]";
  "rq[5013;\"count each .u.w\"]";
  "rq[5011;\"tables[]!count each value each tables[]\"]";
  "procDir 5011";
  "procDir 5012";
  "rq[5012;\"tables[]\"]");

/ run a query on another process by port, over a short-lived handle
rq:{[port;qry] h:hopen port; r:@[h;qry;{`$"remote error: ",x}]; hclose h; r };
/ the working directory of another process
procDir:{[port] r:rq[port;"system\"cd\""]; $[10h=type r; r; first r] };

/ newest tickerplant log under log/
tcaLog:{ f:key `:log; f:f where f like "sym2*"; "log/",string last asc f };

/ ── forced end of day ───────────────────────────────────────────────────
/ tcaEod[] tells the tickerplant to end the day NOW, then checks the result:
/ the RDB writes its tables to log/sym as a date partition and empties itself,
/ the HDB reloads, and the tickerplant rolls to tomorrow's date and log file.
/ It is deliberately not part of tcaDump[]: every call advances the
/ tickerplant's date by one day. Restart the stack afterwards to return to today.
tcaEodQueries:(
  "rq[5010;\".u.d\"]";
  "rq[5011;\"tables[]!count each value each tables[]\"]";
  "rq[5010;\".u.endofday[]\"]";
  "rq[5011;\"tables[]!count each value each tables[]\"]";
  "rq[5010;\"`date`log!(.u.d;.u.L)\"]";
  "rq[5012;\"tables[]\"]";
  "rq[5012;\"select n:count i by date from execs\"]";
  "rq[5012;\"select n:count i by date from quote\"]";
  "rq[5012;\"meta execs\"]";
  "rq[5012;\"5#select from execs where date=last date\"]";
  "rq[5012;\"select n:count i, shares:sum lastQty by date, venue from execs\"]";
  "key `:log/sym");

tcaEod:{[]
  rd:procDir 5011; hd:procDir 5012;
  if[not rd like "*log/sym"; '"RDB is not in log/sym: ",rd];
  if[not hd like "*log/sym"; '"HDB is not in log/sym, start it with  q log/sym -p 5012 : ",hd];
  file:hsym `$getenv[`HOME],"/Code/exec-tca-stack/tcaEod.txt";
  c:system"c"; system"c 2000 2000";
  run:{[q] "q)",q,"\n",@[{.Q.s value x};q;{"'",x,"\n"}],"\n"};
  out:raze run each tcaEodQueries;
  system"c ",(" " sv string c);
  file 0: "\n" vs out;
  -1"wrote ",(1_string file);
  file };

tcaDump:{[]
  file:hsym `$getenv[`HOME],"/Code/exec-tca-stack/tcaData.txt";
  c:system"c"; system"c 2000 2000";                 / wide console so tables are not truncated
  run:{[q] "q)",q,"\n",@[{.Q.s value x};q;{"'",x,"\n"}],"\n"};
  out:raze run each tcaQueries;
  system"c ",(" " sv string c);                     / restore the console size
  file 0: "\n" vs out;
  -1"wrote ",(1_string file);
  file };
