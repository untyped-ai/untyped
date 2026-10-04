# untyped

The protocol around your agent, model-checked.

> Your runtime retries, so a tool call can be dropped, delivered twice, or run with its
> acknowledgement lost. Your harness must still produce at most one effect per step, no
> destructive effect without approval, and no more calls than budgeted. This model checks
> whether it does, in the design and in the runs you recorded.

```sh
git clone https://github.com/untyped-ai/untyped && cd untyped && make all   # Java 11+, nothing else
```

```
ok    correct: no violation (18 distinct states)
ok    bug_key_per_attempt: AtMostOnce violated (6 states)
ok    bug_no_key: AtMostOnce violated (5 states)
ok    bug_approval_proceeds: ApprovalBeforeEffect violated (4 states)
ok    bug_budget_per_attempt: BudgetHeld violated (7 states)
ok    vacuity: NoEffect violated (4 states)
ok    big_correct: no violation (12480 distinct states)
ok    big_bug_key: AtMostOnce violated (5 states)
ok    big_bug_budget: BudgetHeld violated (13 states)
ok    run A: no violation (4 distinct states)
ok    run B: AtMostOnce violated (6 states)
ok    run C: rejected, the run is outside the protocol
ok    run D: no violation (8 distinct states)
```

Each line is a check that must come out exactly as named. `vacuity` checks that
an effect is reachable at all, so the invariants do not hold vacuously.

## What is modelled

`harness.tla` (155 lines) is the protocol between an agent harness and a
side-effecting tool on a durable-execution runtime (Temporal, Inngest, Restate,
DBOS, LangGraph, or hand-rolled retries). The LLM is not modelled: which steps run,
and in what order, is left unconstrained. What is modelled is everything the LLM
does not decide.

| The runtime may (assumptions)          | The harness must (guarantees)                    |
|----------------------------------------|--------------------------------------------------|
| lose the acknowledgement after success | `AtMostOnce`: effect at most once per step       |
| deliver the same attempt twice         | `ApprovalBeforeEffect`: no destructive effect without a recorded approval |
| drop a call before the tool runs       | `BudgetHeld`: total tool calls ≤ budget          |
| retry up to `MaxRetries`               |                                                  |
| let an approval time out               |                                                  |

A concrete harness is a configuration, not a new model:

| Constant            | Values                      | The design decision it names                                  |
|---------------------|-----------------------------|---------------------------------------------------------------|
| `KeyMode`           | `step` / `attempt` / `none` | is the idempotency key minted per logical step or per retry? |
| `OnApprovalTimeout` | `abort` / `proceed`         | what happens when nobody answers the approval request         |
| `BudgetScope`       | `run` / `attempt`           | does the budget counter survive a retry?                      |
| `Destructive`       | subset of `Steps`           | which steps need a human first                                |
| `MaxRetries`, `Budget` | numbers                  | the bounds you actually configured                            |

Each `bug_*.cfg` differs from `correct.cfg` in one line, and TLC prints the
interleaving that breaks the invariant:

```
$ make trace cfg=bug_key_per_attempt      # excerpt
State 3: <Call(s1)>
/\ attempt = (s1 :> 1)
State 4: <LostAck(s1)>
/\ effects = (s1 :> 1)
State 5: <Call(s1)>
/\ attempt = (s1 :> 2)
State 6: <Ack(s1)>
/\ effects = (s1 :> 2)
```

The tool ran and the acknowledgement was lost (state 4). The retry is attempt 2,
and with a per-attempt key it carries a key the tool has not seen, so the tool runs
again (state 6).

`big/` runs the same checks on three steps: 12,480 distinct states for the correct
configuration, about 1.6 s on a laptop.

## Checking a run

Model checking says nothing about the code. Trace validation checks a recorded run
of the real system against the same, unmodified specification (Cirstea, Kuppe,
Loillier, Merz, SEFM 2024, arXiv:2404.16075).

A run is a JSONL file. Line 1 is the configuration under test, each following line
is one event:

```
{"kind":"run","run_id":"B","steps":["refund_42"],"destructive":["refund_42"],"max_retries":2,
 "budget":3,"key_mode":"attempt","on_approval_timeout":"abort","budget_scope":"run"}
{"event":"Grant","step":"refund_42"}
{"event":"Call","step":"refund_42","attempt":1}
{"event":"Timeout","step":"refund_42"}
{"event":"Call","step":"refund_42","attempt":2}
{"event":"Ack","step":"refund_42","effects":2}
```

There are three verdicts, one per TLC exit code:

- **accepted** (exit 0). The run is a behaviour of the protocol and keeps every invariant.
- **violated** (exit 12). The run is a behaviour of the protocol and breaks an invariant.
  The run itself is the counterexample. In run B the harness saw a `Timeout`, the model
  resolves it as `LostAck`, the retry used a new key, and the refund went out twice.
- **rejected** (exit 10). The run is not a behaviour of the protocol at all, and TLC
  names the first event that is not. In run C a destructive `Call` has no `Grant` before it.

Fields the log does not carry (`attempt`, `effects`) are left to the model checker.
A `Timeout` without tool-side data branches into `LostAck` and `Dropped`, and the
verdict covers both. A clean run means "no violation in this run, within these
bounds", not "correct".

```sh
make run TRACE=path/to/your.jsonl     # one run
make validate                        # runs A–D
```

Runs A–D are written by hand in the schema, not recorded. Runs recorded from real
frameworks are in [untyped-ai/receipts](https://github.com/untyped-ai/receipts).

## What it is not

- Not a proof about your code. It checks the protocol you configured, within the
  bounds you stated, and the runs you recorded.
- Not a model of the LLM. No language model is involved anywhere in the check.
- Not a liveness check. The invariants are safety properties. A harness that never
  calls the tool satisfies all three, which is why `vacuity` exists.
- Not a way to recover lost events. A run may omit fields but not events: a step the
  log does not show cannot be inferred, and if it changed what the log shows, the run
  is rejected rather than marked violated.
- Not runtime enforcement. It checks designs and records. It does not sit in the call path.

## Layout

```
harness.tla              the protocol model
*.cfg                    six one-step configurations, including the vacuity check
big/                     three-step configurations
trace/harnessTrace.tla   trace validation (67 lines), runs A–D
check.sh, Makefile       make check | big | validate | all | run | trace
tools/                   pinned TLA+ tools and CommunityModules (see tools/README.md)
```

MIT. Made by [untyped.ai](https://untyped.ai). Contact: hello [at] untyped.ai
