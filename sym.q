/ exec-tca-stack : schema
/ One event table per message class. Orders are a hierarchy: a parent (the PM's
/ order) is worked as one or more algo orders (one per broker algo), each sliced
/ into child orders, each of which may fill several times.
/ One event table per message class. tick.q loads this as its schema file,
/ so every table must open with `time`sym (tick.q enforces 2#key = `time`sym)
/ and carry `g#sym for fast by-sym selection in the RDB and CEP.
/ `time` is a timespan (intraday, time-of-day): the tickerplant stamps it on
/ receipt, so feeds publish every column EXCEPT time. Horizons and windows are
/ therefore timespans too (00:00:01, 00:00:10, 00:01:00).

quote:([]                                   / top of book, per venue
  time:`timespan$(); sym:`g#`symbol$(); venue:`symbol$();
  bid:`float$(); ask:`float$(); bsize:`long$(); asize:`long$() )

trade:([]                                   / the consolidated tape (prints)
  time:`timespan$(); sym:`g#`symbol$(); venue:`symbol$();
  px:`float$(); size:`long$() )

ord:([]                                      / order events: new / replace / cancel
  time:`timespan$(); sym:`g#`symbol$(); parentOrderID:`symbol$();
  algoOrderID:`symbol$(); algo:`symbol$(); childOrderID:`symbol$();
  side:`char$(); ordType:`char$(); qty:`long$(); limitPx:`float$();
  tif:`char$(); venue:`symbol$(); msgType:`symbol$() )

execs:([]                                     / execution reports (fills, busts, acks)
  time:`timespan$(); sym:`g#`symbol$(); parentOrderID:`symbol$();
  algoOrderID:`symbol$(); algo:`symbol$(); childOrderID:`symbol$();
  side:`char$(); execType:`char$(); lastPx:`float$(); lastQty:`long$();
  leaves:`long$(); cumQty:`long$(); venue:`symbol$(); liq:`char$() )

/ ── reference data every process agrees on ──────────────────────────────
uni:`AAPL`MSFT`NVDA`AMZN`TSLA`META`GOOGL`JPM         / the traded universe
refPx:uni!182.4 418.1 121.7 178.9 244.3 503.6 166.2 201.8   / anchor prices
/ venues: four lit, one dark midpoint pool, one internaliser (house flow)
venues:`ARCA`NSDQ`BATS`EDGX`MLIT`INTL
lit:`ARCA`NSDQ`BATS`EDGX
dark:`MLIT                                           / midpoint, prints to tape late
house:`INTL                                          / internalised — never touches the street
session:09:30:00.000 16:00:00.000                    / regular-hours window
