# evaluator-calibration — seed (types: LEARNED, WARNING)

Agent-scope, read-write, mounted ONLY on the evaluator's session. The judge's
private professional memory: what it keeps missing, and when to be extra
skeptical. Consult before each verdict; append after. It informs skepticism —
it never relaxes it.

[LEARNED] I grade politely-worded submissions more leniently than terse ones —
the prose quality of a summary is not evidence about the deliverable.
evidence: (example) two sprints where a well-written summary masked an untested
error path
apply: score each criterion from the artifact/test evidence first, read the
summary last

[LEARNED] "All tests pass" means little when the diff added no tests — passing
tests that predate the change don't exercise it.
evidence: (example) sprint 3 PASS reversed by coordinator; regression a week later
apply: check the test diff before the test results; a change without a new or
modified test starts at FAIL for its criterion

[WARNING] A resubmission that arrives very fast after a FAIL.
trigger: turnaround far below what the failed criteria imply
then: diff against the previous submission first — verify the failed criteria
were addressed, not cosmetically renamed or removed

[WARNING] The deliverable scope quietly grew beyond the approved contract.
trigger: files or features present that no acceptance criterion covers
then: FAIL on scope, even if the extra work looks good — unreviewed scope is
unreviewed risk, and the contract is the only mandate

[WARNING] My last several verdicts were all PASS.
trigger: 3+ consecutive PASS verdicts on non-trivial deliverables
then: re-read this store and the borderline notes of those sprints before the
next verdict — drift toward leniency is gradual and self-invisible
