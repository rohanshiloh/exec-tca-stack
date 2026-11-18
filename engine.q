/ exec-tca-stack : the TCA engine
/ State, event handlers, the upd entry point, and the benchmark wrappers.
/ Loaded by tca.q (live, chained-TP subscriber) and replay.q (batch, log replay),
/ so one code path serves both real-time and after-the-fact TCA.
\l sym.q
\l bench.q
\l beyond.q

/ ── live state ───────────────────────────────────────────────────────────
topMid:(`symbol$())!`float$();                         / consolidated mid per sym
parent:([parentOrderID:`symbol$()] sym:`symbol$(); side:`char$(); qty:`long$();
  arrivalTime:`timespan$(); arrivalMid:`float$(); filledQty:`long$(); notional:`float$());
/ one level down: each algo order, with its own arrival mid (the mid when the algo got it)
algoOrd:([algoOrderID:`symbol$()] parentOrderID:`symbol$(); sym:`symbol$(); side:`char$();
  algo:`symbol$(); qty:`long$(); arrivalTime:`timespan$(); arrivalMid:`float$();
  filledQty:`long$(); notional:`float$());

/ handlers at top-level (no namespace): KDB-X does not fall back to root for reads
/ SIMPLIFICATION: takes the LAST venue in the batch, not a true consolidated NBBO
/ (which would be max bid / min ask across the lit venues).
updTop:{[d] a:0!select mid:last 0.5*bid+ask by sym from d; `topMid upsert (a`sym)!a`mid };
/ a NEW with no algoOrderID is the parent; a NEW with one is an algo order
onOrd:{[d] d:select from d where msgType=`NEW;
  p:select from d where null algoOrderID;
  if[count p; `parent upsert 0!select parentOrderID, sym, side, qty,
     arrivalTime:time, arrivalMid:topMid sym, filledQty:0, notional:0f from p];
  a:select from d where not null algoOrderID;
  if[count a; `algoOrd upsert 0!select algoOrderID, parentOrderID, sym, side, algo, qty,
     arrivalTime:time, arrivalMid:topMid sym, filledQty:0, notional:0f from a] };
onExec:{[d] d:select from d where execType="F";
  if[0=count d; :()];
  g:select fillQty:sum lastQty, fillNotional:sum lastPx*lastQty by parentOrderID from d;
  p:(0!select from parent where parentOrderID in (0!g)`parentOrderID) lj g;
  `parent upsert delete fillQty,fillNotional from
     update filledQty:filledQty+fillQty, notional:notional+fillNotional from p;
  g:select fillQty:sum lastQty, fillNotional:sum lastPx*lastQty by algoOrderID from d;
  a:(0!select from algoOrd where algoOrderID in (0!g)`algoOrderID) lj g;
  `algoOrd upsert delete fillQty,fillNotional from
     update filledQty:filledQty+fillQty, notional:notional+fillNotional from a };

/ ── upd: insert the batch, then advance derived state ────────────────────
upd:{[t;x] t insert x;
  d:$[98h=type x; x; flip (cols t)!x];              / table (live) vs column-list (replay)
  $[t=`quote; updTop d;
    t=`ord;   onOrd  d;
    t=`execs; onExec d; (::)] };

/ ── benchmark wrappers over the live tables (type these at the prompt) ────
HORIZONS:0D00:00:01 0D00:00:10 0D00:01:00;
arrival:{ .b.arrival[parent;execs] };
vwap:{ .b.ivwap[parent;trade;execs] };
markouts:{ .b.markout[execs;quote;HORIZONS] };
scorecard:{ .b.scorecard markouts[] };
spreads:{ .b.spreads[execs;quote;0D00:00:10] };
ofi:{ .b.ofi[quote;0D00:00:05] };
pov:{ .b.participation[parent;trade;execs] };
vcurve:{ .b.volcurve trade };
closes:{ .b.closePx trade };
algoArrival:{ .b.algoArrival[algoOrd;execs] };         / slippage per algo order
algos:{ .b.algoScorecard algoArrival[] };               / and per algo: what the wheel reads

/ beyond-vanilla wrappers (beyond.q)
robust:{ .b.robustArrival[parent;quote;0D00:00:01] };
fees:{ .b.feeAware[execs;quote] };
cohorts:{ arrival[] lj .b.cohort ord };
limited:{ t:(vwap[] lj .b.cohort ord); t:select from t where cohort=`limited;
  g:.b.limVwap[trade];
  update inLimitVwap:g'[sym;startTime;endTime;side;limitPx] from t };
pwp:{ .b.pwpTable[parent;trade;execs;0.2] };
bands:{ .b.pitBands[execs;quote] };
context:{ .b.contextNorm[parent;execs;quote] };
peers:{ .b.pctScore[parent;execs] };
/ the wheel: arrival slippage per algo order, fitted on which algo it went to.
/ Each coefficient is bps relative to VWAP, after allowing for limit and size.
wheel:{ f:.b.wheelData[algoOrd;execs;ord];
  X:flip (count[f]#1f; f`isPOV; f`isARRIVAL; f`isDARK; f`limited; f`sizeK);
  r:.b.olsFit[X; f`slipBps];
  ([] driver:`VWAP`POV`ARRIVAL`DARK`limited`sizeK; bpsPerUnit:r 0; stdErr:r 1; tStat:r[0]%r 1) };
/ why: the same slippage per parent, fitted on how each one was traded
drivers:{ f:.b.wheelFeatures[parent;trade;execs;ord];
  X:flip (count[f]#1f; f`limited; f`pov; f`sizeK; f`passiveShare; f`toxicShare; f`darkShare);
  ([] driver:`intercept`limited`pov`sizeK`passiveShare`toxicShare`darkShare;
      bpsPerUnit:.b.wheelFit[X; f`slipBps]) };
