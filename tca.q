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
  delete from `parent; delete from `algoOrd; delete from `alerts; delete from `venueAlerts;
  topMid::(`symbol$())!`float$();                   / no stale mid from yesterday
  -1"end of day ",string[d],": intraday state cleared"; };

/ F8 live: every 10s, append any algo running away from its own baseline.
/ Exception-based: the table stays empty until something needs a human.
alerts:([] time:`timespan$(); algo:`symbol$(); n:`long$(); recentBps:`float$();
  baseBps:`float$(); z:`float$(); recentFill:`float$(); baseFill:`float$());
venueAlerts:([] time:`timespan$(); venue:`symbol$(); n:`long$(); recentBps:`float$();
  baseBps:`float$(); z:`float$());
/ one alert per episode: an algo or venue already flagged in the last 2 minutes waits
.z.ts:{ if[0=count execs; :()]; now:max execs`time;
  e:exceptions[]; e:select from e where not algo in exec algo from alerts where time>now-0D00:02;
  if[count e; `alerts insert (cols alerts)#update time:now from e];
  v:venueExceptions[]; v:select from v where not venue in exec venue from venueAlerts where time>now-0D00:02;
  if[count v; `venueAlerts insert (cols venueAlerts)#update time:now from v] };
system"t 10000";

-1"tca → subscribed @ ",TP,"   try:  arrival[]  scorecard[]  algoScorecard[]  wheelPaired[]  alerts  venueAlerts";
