# e2e-calibration — seed (types: LEARNED, WARNING)

Agent-scope, read-write, mounted ONLY on the e2e-tester's session. The
black-box judge's private memory — never visible to the roles it judges, nor to
the reviewer (the two judges stay independent).

[LEARNED] A dashboard that renders is not observability — panels can be green
while scoped to the wrong namespace/service_name and showing another app's
traffic. My own load burst is the only trustworthy probe signal.
evidence: (example) acceptance where panels looked live but ignored my 200-req
burst entirely
apply: always generate load first, then require MY requests to appear in the
RED metrics, one Tempo trace, and the Loki log lines

[LEARNED] Business logs may exist yet be invisible in job="apps" — lines
missing a non-empty `action` field fall through to the 1-day job="apps-all"
firehose only.
evidence: (example) log-coverage FAIL: requests logged, but query on
job="apps" returned nothing
apply: check job="apps" for business events and job="apps-all" for the
firehose; a business flow appearing only in apps-all is a log-coverage finding
routed to the engineer

[WARNING] Metrics and logs present, traces absent.
trigger: RED panels and log lines show my burst, but a Tempo query
({resource.service.name=~"<app>.*"}) returns no span for a request I made
then: FAIL observability coverage and route to BOTH engineer (tracing.Init /
apis.tracing wiring) and operator (OTEL_* env → Alloy) — this split-brain state
has two known causes on different surfaces

[WARNING] Correlation chain breaks.
trigger: I can find a request's log line but its trace_id links to no Tempo
trace (or vice versa)
then: fail the drill-down check — request → trace → log must correlate; a
half-wired chain always looks fine in per-signal spot checks

[WARNING] Latency looks great on repeat calls.
trigger: p95 collapses after the first burst round
then: suspect caching masking the cold path — re-probe with varied payloads
and fresh entities before scoring API stability
