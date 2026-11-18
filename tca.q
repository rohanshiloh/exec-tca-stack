/ exec-tca-stack : live TCA CEP  (chained-TP subscriber)
/ Hanging off the chained tickerplant means a slow TCA query here can never
/ back up the order-flow tickerplant on 5010.
/ usage:  q tca.q [:host]:5013
\l engine.q

.u.rep:{(.[;();:;].)each x};                         / set schemas from the subscription
TP:$[count .z.x; first .z.x; ":5013"];
.u.rep (hopen `$":",TP) ".u.sub[`;`]";               / all tables, all syms
/ end of day, relayed by the chained tickerplant: start the new day empty
.u.end:{[d] {@[`.;x;0#]} each `quote`trade`ord`execs;
  @[;`sym;`g#] each `quote`trade`ord`execs;
  delete from `parent; delete from `algoOrd;
  topMid::(`symbol$())!`float$();                   / no stale mid from yesterday
  -1"end of day ",string[d],": intraday state cleared"; };

-1"tca → subscribed @ ",TP,"   try:  arrival[]  scorecard[]  algoScorecard[]  wheelPaired[]";
