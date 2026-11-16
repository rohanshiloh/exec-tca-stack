/ exec-tca-stack : CTRL-tab helpers
/ A scratch process to drive the stack by hand: open a handle to every process,
/ check they are up, and round bps for display.
/ usage:  q lab.q
procs:`TP`RDB`HDB`CTP`TCA!5010 5011 5012 5013 5014;
ping:{ @[{hclose hopen x;`up};x;`down] };
status:{ flip `proc`port`state!(key procs; value procs; ping each value procs) };
h:{ hopen procs x };                          / h`TCA -> handle to the CEP
bps:{ 0.01*floor 0.5+100*x };                 / round to 2dp for the eye
-1"lab → status[] to ping all five; h`TCA to open the CEP; e.g. (h`TCA)\"scorecard[]\"";
