---------------------------- MODULE harnessTrace ----------------------------
(* Trace validation for harness.tla: is a recorded run a behaviour of the     *)
(* configured protocol, and do the invariants hold on it?                     *)
(* Each log line must be exactly one step of the spec. Fields may be missing, *)
(* and the spec then decides their values; events may not. A step the log     *)
(* omits, such as an unlogged redelivery, cannot be inferred: if it changed   *)
(* what the log shows, the run is rejected.                                   *)
EXTENDS harness, Json, IOUtils, Sequences, TLC

ASSUME TLCGet("config").mode = "bfs"

\* TRACE=path/to/run.jsonl  (falls back to trace.jsonl)
JsonFile == IF "TRACE" \in DOMAIN IOEnv THEN IOEnv.TRACE ELSE "trace.jsonl"
Log      == ndJsonDeserialize(JsonFile)

\* Line 1 is the run header: constants of the configuration under test.
Header == Log[1]
Events == SubSeq(Log, 2, Len(Log))

Seq2Set(q) == {q[i] : i \in DOMAIN q}
TraceSteps             == Seq2Set(Header.steps)
TraceDestructive       == Seq2Set(Header.destructive)
TraceMaxRetries        == Header.max_retries
TraceBudget            == Header.budget
TraceKeyMode           == Header.key_mode
TraceOnApprovalTimeout == Header.on_approval_timeout
TraceBudgetScope       == Header.budget_scope

VARIABLE l              \* index of the next event line to consume
logline == Events[l]

TraceInit == l = 1 /\ Init

\* Consume line l if it carries event e.
At(e) == /\ l \in 1..Len(Events)
         /\ logline.event = e
         /\ l' = l + 1

\* Optional observations, checked only when the line carries them.
ObservedAttempt(s) == "attempt" \in DOMAIN logline => attempt'[s] = logline.attempt
ObservedEffects(s) == "effects" \in DOMAIN logline => effects'[s] = logline.effects

IsGrant       == At("Grant")       /\ Grant(logline.step)
IsGateTimeout == At("GateTimeout") /\ GateTimeout(logline.step)
IsCall        == At("Call")        /\ Call(logline.step)      /\ ObservedAttempt(logline.step)
IsAck         == At("Ack")         /\ Ack(logline.step)       /\ ObservedEffects(logline.step)
IsLostAck     == At("LostAck")     /\ LostAck(logline.step)   /\ ObservedEffects(logline.step)
IsDropped     == At("Dropped")     /\ Dropped(logline.step)   /\ ObservedEffects(logline.step)
IsRedeliver   == At("Redeliver")   /\ Redeliver(logline.step) /\ ObservedEffects(logline.step)
\* Harness saw a timeout and does not know whether the tool ran: either branch.
IsTimeout     == At("Timeout")     /\ (LostAck(logline.step) \/ Dropped(logline.step))
                                   /\ ObservedEffects(logline.step)

TraceNext ==
  \/ IsGrant \/ IsGateTimeout \/ IsCall \/ IsAck
  \/ IsLostAck \/ IsDropped \/ IsRedeliver \/ IsTimeout

TraceSpec == TraceInit /\ [][TraceNext]_<<vars, l>>

TraceView == <<vars, l>>

\* Poor man's hyperproperty: at least one behaviour consumed the whole log.
TraceAccepted ==
  LET d == TLCGet("stats").diameter IN
  IF d - 1 = Len(Events) THEN TRUE
  ELSE Print(<<"Trace rejected at event line", d, Events[d]>>, FALSE)
=============================================================================
