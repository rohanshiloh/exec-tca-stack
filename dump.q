/ exec-tca-stack : write TCA diagnostics to tcaData.txt
/ usage, in the TCA tab:   \l dump.q      then   tcaDump[]
/ Each query is trapped, so one failure prints its error and the rest still run.
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
  "5#pov[]";
  "select n:count i, avgPov:avg pov, medPov:med pov, maxPov:max pov from pov[]";
  "closes[]";
  "select lo:min bid, hi:max bid, avgSpread:avg ask-bid by sym from quote";
  "vcurve[]";
  "5#0!parent";
  "select pctFilled:filledQty%qty, vwapFill:notional%filledQty by parentOrderID from 5#0!parent";
  "select wAvg:fillRate wavg slipBps from arrival[]";
  "select averageBps:avg bps by horizon from markouts[]";
  "select averageBps:avg bps, medBps:med bps, clampedBps:avg -25f|25f&bps, n:count i by venue from markouts[]";
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
  "select n:count i, avgCost:avg cost, medCost:med cost by side, szBucket from peers[]");

tcaDump:{[]
  file:hsym `$getenv[`HOME],"/Code/exec-tca-stack/tcaData.txt";
  c:system"c"; system"c 2000 2000";                 / wide console so tables are not truncated
  run:{[q] "q)",q,"\n",@[{.Q.s value x};q;{"'",x,"\n"}],"\n"};
  out:raze run each tcaQueries;
  system"c ",(" " sv string c);                     / restore the console size
  file 0: "\n" vs out;
  -1"wrote ",(1_string file);
  file };
