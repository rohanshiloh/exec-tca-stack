/ exec-tca-stack : live TCA CEP  (chained-TP subscriber)
/ Hanging off the chained tickerplant means a slow TCA query here can never
/ back up the order-flow tickerplant on 5010.
/ usage:  q tca.q [:host]:5013
\l engine.q

.u.rep:{(.[;();:;].)each x};                         / set schemas from the subscription
TP:$[count .z.x; first .z.x; ":5013"];
.u.rep (hopen `$":",TP) ".u.sub[`;`]";               / all tables, all syms
-1"tca → subscribed @ ",TP,"   try:  arrival[]  markouts[]  scorecard[]  ofi[]";
