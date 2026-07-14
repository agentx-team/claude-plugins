# project-context — seed (types: FACT, LEARNED)

Project-scope, read-write. This project's decisions and accumulated delivery
experience. The examples show the shape; the first real service replaces them.

[FACT] Services in this project derive from github.com/aws300/scaffold:
proto-first ConnectRPC backends (Go/Python) + SolidJS frontend + Helm chart for
Envoy Gateway and AWS IRSA. The repo's CONTRIBUTING.md, protos/Makefile,
scripts/deploy.sh and .github/workflows/ ARE the process spec.
source: project setup

[FACT] Observability is toggled by the single `scaffold.observability` values
block; the app adds no extra pods (only backend annotations/env + a one-shot
dashboard sync Job). Dashboards use datasource UIDs PROMETHEUS/LOKI/TEMPO and
scope every query by namespace/service_name.
source: scaffold charts/OBSERVABILITY.md

[LEARNED] Go spans silently vanish when only `apis.tracing: true` is set —
`common-go/grpcmux` creates spans but installs no exporter; without
`tracing.Init()` in main.go they are dropped. Both are required.
evidence: (example) accept-service FAIL on observability coverage — Grafana had
metrics and logs but zero Tempo traces
apply: engineer checks both flags whenever traces are in the contract; operator
verifies a trace arrives in Tempo before handing to review

[LEARNED] Dashboards provisioned per-app via dynamic efs-sc PVCs never show up
in Grafana — dynamic provisioning isolates each PVC in its own directory, so
Grafana's Apps provider can't see them. Use the static PV/PVC pair pointing at
the shared EFS access point, and confirm the EFS IDs match base's values.
evidence: (example) ship-service NO-GO — sync Job green but folder empty in
Grafana
apply: operator copies the static PV/PVC pattern from the scaffold chart and
diff-checks efsFileSystemId/efsAccessPointId against base/values.yaml
