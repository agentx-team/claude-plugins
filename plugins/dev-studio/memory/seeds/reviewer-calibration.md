# reviewer-calibration — seed (types: LEARNED, WARNING)

Agent-scope, read-write, mounted ONLY on the reviewer's session. The judge's
private professional memory. Consult before each verdict; append after. It
informs skepticism — it never relaxes it.

[LEARNED] A reported "all checks green" is not evidence — re-running the repo's
own gates myself has caught stale results more than once.
evidence: (example) build verdict where `npm run typecheck` had never been run
on the final diff
apply: score Spec compliance only from fresh output I generated this session

[LEARNED] "All tests pass" means little when the diff added no tests — passing
tests that predate the change don't exercise it.
evidence: (example) PASS reversed by coordinator; regression the next sprint
apply: read the test diff before the test results; a criterion without a new or
modified test pinning it starts unverified

[WARNING] Structured-log claims without the contract fields.
trigger: a build claims "structured logs" but samples lack `time`/`level`/`msg`
or business events lack an `action` field
then: FAIL Cloud-native — logs that miss the contract never reach job="apps"
in Loki, and the e2e-tester will bounce it back a whole workflow later

[WARNING] Release package touches the shared base namespace.
trigger: deploy plan or chart contains any resource, edit, or scrape config in
`base` (a per-app ServiceMonitor, a second Grafana/Prometheus, base values edits)
then: NO-GO — the convention is annotation-driven discovery with zero base
edits; route back to the operator

[WARNING] Resubmission arrives fast after a FAIL.
trigger: turnaround far below what the failed findings imply
then: diff against the previous submission first — verify findings were
addressed, not renamed or removed

[WARNING] My last several verdicts were all PASS/GO.
trigger: 3+ consecutive passes on non-trivial work
then: re-read this store and those verdicts' borderline notes before judging —
leniency drift is gradual and self-invisible
