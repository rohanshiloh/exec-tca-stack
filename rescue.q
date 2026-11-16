/ exec-tca-stack : recover a truncated / corrupt tickerplant log
/ The exec log is the audit trail: if the TP (or the box) died mid-write, the
/ tail is a half-written chunk and a plain -11!L throws. This finds the last
/ valid message, truncates the file to the valid prefix, and verifies it.
/ usage:  q rescue.q log/sym2026.11.12
\l sym.q

L:`$":",first .z.x;
/ -11!(-2;L) returns a long ATOM (message count) when the log is clean, and a
/ 2-item list (validMsgs; validBytes) only when it is corrupt — same test tick.q
/ uses in .u.ld:  if[0<=type i; ...corrupt...]
chk:-11!(-2;L);

$[(type chk)<0;
  -1"log is clean: ",string[chk]," messages, nothing to do.";
  [ good:chk 0; bytes:chk 1;
    -1"corrupt after ",string[good]," msgs / ",string[bytes]," of ",
      string[hcount L]," bytes — truncating to the valid prefix";
    keep:(read1 L) til bytes;                / the bytes that parse cleanly
    hdel L; L 1: keep;                        / overwrite with the valid prefix only
    -1"recovered: ",string[-11!(-2;L)]," messages now replay cleanly." ] ];
/ the TP can now reopen and continue appending to L, and replay.q can read it.
