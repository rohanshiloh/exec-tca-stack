/ exec-tca-stack : after-the-fact TCA by replaying a tickerplant log
/ Re-runs a past day's order flow through the SAME engine the live CEP uses,
/ so last night's numbers and this morning's are computed by identical code.
/ usage:  q replay.q log/sym2026.11.12        (a tickerplant log)
\l engine.q

L:`$":",first .z.x;
-1"replaying ",string[L]," through the engine …";
n:-11!L;                                     / stream every (`upd;t;x) chunk through upd
-1"  replayed ",string[n]," messages → ",string[count parent]," parents, ",
  string[count execs]," fills";

/ batch TCA over the reconstructed day
-1"\n── arrival slippage (bps, + = favourable) ──";
show select parentOrderID, sym, side, qty, fillRate, slipBps from arrival[];
-1"\n── venue scorecard ──";
show scorecard[];
-1"\n── OFI by sym ──";
show ofi[];
