check:    ; @./check.sh protocol
big:      ; @./check.sh big
validate: ; @./check.sh trace
all:      ; @./check.sh all

# Verdict for one recorded run: make run TRACE=path/to/run.jsonl
run:      ; @./check.sh run $(TRACE)

# Print the interleaving behind a verdict: make trace cfg=bug_key_per_attempt
trace:
	@java -XX:+UseSerialGC -cp tools/tla2tools.jar tlc2.TLC -config $(cfg).cfg -workers 1 -deadlock \
	  -metadir $${TMPDIR:-/tmp}/harness-states harness.tla \
	  | grep -E "^Error: Invariant|^State|^/\\\\ (effects|attempt|calls|gate) =" \
	  | sed -E 's/ line [0-9]+, col [0-9]+ to line [0-9]+, col [0-9]+ of module [A-Za-z]+//'

.PHONY: check big validate all run trace
