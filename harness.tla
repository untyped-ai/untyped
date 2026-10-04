------------------------------- MODULE harness -------------------------------
(* The protocol around an LLM agent, not the LLM.                             *)
(* One logical step = one side-effecting tool call (refund, delete, send).    *)
(* The runtime retries: a call can be dropped, delivered twice, or run with   *)
(* its acknowledgement lost.                                                  *)
(* Whatever it does, the harness must produce at most one effect per step,    *)
(* no destructive effect without approval, and no more calls than budgeted.   *)
(* The LLM is not modelled: which steps run, and in what order, is left       *)
(* unconstrained. Only safety is specified; nothing here promises progress.   *)
EXTENDS Naturals, FiniteSets

CONSTANTS
  Steps,             \* logical steps, each one side-effecting tool call
  Destructive,       \* steps that need a recorded human approval first
  MaxRetries,        \* runtime retry limit per step (attempts = MaxRetries+1)
  Budget,            \* maximum number of tool calls the run may make
  KeyMode,           \* "step" | "attempt" | "none"  : how the idempotency key is derived
  OnApprovalTimeout, \* "abort" | "proceed"          : what the gate does when nobody answers
  BudgetScope        \* "run"  | "attempt"           : what the budget counter actually counts

ASSUME Destructive \subseteq Steps
ASSUME KeyMode \in {"step", "attempt", "none"}
ASSUME OnApprovalTimeout \in {"abort", "proceed"}
ASSUME BudgetScope \in {"run", "attempt"}
ASSUME MaxRetries \in Nat /\ Budget \in Nat

VARIABLES
  \* harness
  attempt,     \* [Steps -> Nat]      attempts made so far
  inflight,    \* [Steps -> BOOLEAN]  call sent, answer not yet seen by the harness
  acked,       \* [Steps -> BOOLEAN]  harness holds a success acknowledgement
  aborted,     \* [Steps -> BOOLEAN]  harness gave up on the step
  calls,       \* Nat                 tool calls made in the whole run
  \* approval gate
  gate,        \* [Steps -> {"pending", "granted", "timedout"}]
  \* runtime
  redelivered, \* [Steps -> BOOLEAN]  the current attempt has already been delivered twice
  \* tool
  effects,     \* [Steps -> Nat]      times the tool actually performed the effect
  seenKeys     \* SUBSET (Steps \X Nat) idempotency keys the tool has seen

vars == <<attempt, inflight, acked, aborted, calls, gate, redelivered, effects, seenKeys>>

TypeOK ==
  /\ attempt     \in [Steps -> 0..MaxRetries + 1]
  /\ inflight    \in [Steps -> BOOLEAN]
  /\ redelivered \in [Steps -> BOOLEAN]
  /\ acked       \in [Steps -> BOOLEAN]
  /\ aborted     \in [Steps -> BOOLEAN]
  /\ gate        \in [Steps -> {"pending", "granted", "timedout"}]
  /\ effects     \in [Steps -> Nat]
  /\ seenKeys    \subseteq Steps \X Nat
  /\ calls       \in Nat

\* Idempotency key the harness attaches to attempt a of step s.
Key(s, a) == IF KeyMode = "step" THEN <<s, 0>> ELSE <<s, a>>

\* Budget check as the harness implements it. With scope "attempt" the counter
\* is reset by the runtime on every retry, so the check never trips.
BudgetOK == IF BudgetScope = "run" THEN calls < Budget ELSE TRUE

\* A human approval is recorded exactly when the gate was granted.
Approved(s) == gate[s] = "granted"

GateOpen(s) ==
  \/ s \notin Destructive
  \/ gate[s] = "granted"
  \/ gate[s] = "timedout" /\ OnApprovalTimeout = "proceed"

Init ==
  /\ attempt     = [s \in Steps |-> 0]
  /\ inflight    = [s \in Steps |-> FALSE]
  /\ redelivered = [s \in Steps |-> FALSE]
  /\ acked       = [s \in Steps |-> FALSE]
  /\ aborted     = [s \in Steps |-> FALSE]
  /\ gate        = [s \in Steps |-> IF s \in Destructive THEN "pending" ELSE "granted"]
  /\ effects     = [s \in Steps |-> 0]
  /\ seenKeys    = {}
  /\ calls       = 0

\* --- approval gate -----------------------------------------------------------
Grant(s) ==
  /\ gate[s] = "pending"
  /\ gate' = [gate EXCEPT ![s] = "granted"]
  /\ UNCHANGED <<attempt, inflight, redelivered, acked, aborted, effects, seenKeys, calls>>

GateTimeout(s) ==
  /\ gate[s] = "pending"
  /\ gate'    = [gate EXCEPT ![s] = "timedout"]
  /\ aborted' = [aborted EXCEPT ![s] = (OnApprovalTimeout = "abort")]
  /\ UNCHANGED <<attempt, inflight, redelivered, acked, effects, seenKeys, calls>>

\* --- harness sends a call ------------------------------------------------------
Call(s) ==
  /\ ~acked[s] /\ ~inflight[s] /\ ~aborted[s]
  /\ attempt[s] <= MaxRetries
  /\ GateOpen(s)
  /\ BudgetOK
  /\ attempt'     = [attempt EXCEPT ![s] = @ + 1]
  /\ inflight'    = [inflight EXCEPT ![s] = TRUE]
  /\ redelivered' = [redelivered EXCEPT ![s] = FALSE]
  /\ calls'       = calls + 1
  /\ UNCHANGED <<acked, aborted, gate, effects, seenKeys>>

\* --- tool executes the delivered call --------------------------------------------
ToolRun(s) ==
  LET k == Key(s, attempt[s]) IN
  /\ effects'  = IF KeyMode = "none" \/ k \notin seenKeys
                 THEN [effects EXCEPT ![s] = @ + 1] ELSE effects
  /\ seenKeys' = seenKeys \cup {k}

\* Tool ran, acknowledgement reaches the harness.
Ack(s) ==
  /\ inflight[s]
  /\ ToolRun(s)
  /\ acked'    = [acked EXCEPT ![s] = TRUE]
  /\ inflight' = [inflight EXCEPT ![s] = FALSE]
  /\ UNCHANGED <<attempt, redelivered, aborted, gate, calls>>

\* Tool ran, acknowledgement is lost: timeout after success. Harness will retry.
LostAck(s) ==
  /\ inflight[s]
  /\ ToolRun(s)
  /\ inflight' = [inflight EXCEPT ![s] = FALSE]
  /\ UNCHANGED <<attempt, redelivered, acked, aborted, gate, calls>>

\* Call dropped before the tool ran. Harness will retry.
Dropped(s) ==
  /\ inflight[s]
  /\ inflight' = [inflight EXCEPT ![s] = FALSE]
  /\ UNCHANGED <<attempt, redelivered, acked, aborted, gate, effects, seenKeys, calls>>

\* Runtime delivers the same attempt a second time. One duplicate per attempt is
\* enough: a key that deduplicates one copy deduplicates any number of them.
Redeliver(s) ==
  /\ inflight[s] /\ ~redelivered[s]
  /\ ToolRun(s)
  /\ redelivered' = [redelivered EXCEPT ![s] = TRUE]
  /\ UNCHANGED <<attempt, inflight, acked, aborted, gate, calls>>

Next ==
  \E s \in Steps :
    Grant(s) \/ GateTimeout(s) \/ Call(s) \/ Ack(s) \/ LostAck(s) \/ Dropped(s) \/ Redeliver(s)

Spec == Init /\ [][Next]_vars

\* --- what the harness must guarantee, whatever the runtime does ----------------
AtMostOnce           == \A s \in Steps : effects[s] <= 1
ApprovalBeforeEffect == \A s \in Destructive : effects[s] > 0 => Approved(s)
BudgetHeld           == calls <= Budget

\* Vacuity witness, checked by vacuity.cfg and expected to be violated: some step
\* does perform its effect, so the invariants above do not hold vacuously.
NoEffect             == \A s \in Steps : effects[s] = 0
=============================================================================
