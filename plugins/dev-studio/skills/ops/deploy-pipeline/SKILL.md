---
name: deploy-pipeline
description: |
  Package a service for the team's Kubernetes cluster the scaffold way — Helm chart
  (backend/frontend/HTTPRoute/serviceaccount), Envoy Gateway routing, AWS IRSA, arm64 images to
  ghcr.io — and wire observability into the cluster's EXISTING Prometheus/Loki/Tempo/Grafana, then
  stage a deploy + rollback plan for a human operator.

  Use when: preparing a delivered service for deploy, authoring the Helm chart/values, or wiring
  dashboards/alerts. Triggers on "package for deploy", "helm chart", "deploy plan", "rollback",
  "add monitoring", "dashboards", "alerts", "observability".

  Not for: building the service (use scaffold-build) or running it live (deploy is a human action).
---

# Deploy Pipeline

The scaffold repo (**github.com/aws300/scaffold**) encodes the deploy contract; mirror it rather
than inventing one. **Nothing here runs against a live cluster** — every cluster action is written
into a plan for a human operator.

## The source of truth (read these first)

| The "how" | Lives in |
|-----------|----------|
| Image build → chart publish → deploy shape | `scripts/deploy.sh` |
| Chart templates: backend, frontend, HTTPRoute, serviceaccount | `charts/templates/` |
| Per-service values (hostname, IRSA role, image, replicas, probes) | `charts/values.yaml` |
| CI deploy/release gates | `.github/workflows/aws_eks.yml`, `release.yml` |

## Package the chart

Set per-service values: `global.gateway`/`gatewayNamespace`, `host.frontend` (+ `host.backend` if
separate), `image.*` (**digest-pinned** — a mutable tag won't force a node re-pull), `irsaRoleArn`
(least-privilege), replicas, resources, readiness/liveness. Build images for **`linux/arm64`** (the
cluster runs arm64 nodes), push to `ghcr.io`, reference by digest. Secrets come from cluster
secrets / IRSA — never baked into chart or image.

## Wire observability into the EXISTING stack

The cluster already runs the shared monitoring stack — discover real endpoints with read-only
`kubectl get/describe` and target them via Helm values. **Never stand up a second stack.**

- **Metrics → Prometheus** — `/metrics` + a `ServiceMonitor`/scrape annotations.
- **Logs → Loki (via Alloy)** — structured JSON to stdout; define the label set.
- **Traces → Tempo** — OTLP exporter pointed at the in-cluster endpoint.
- **Dashboards & alerts → Grafana** — RED metrics per RPC; actionable alerts (threshold + duration
  + runbook) for error rate, latency, crashloop.

## Produce (under `src/deploy/`)

1. Chart overrides/values for this service.
2. `deploy-plan.md` — the exact operator commands (build+push arm64 images, `helm upgrade --install
   ... -n <ns> --set image...@<digest>`, post-deploy health check), and the target namespace.
3. `rollback-plan.md` — `helm rollback` / previous pinned digest, plus how to confirm healthy.
4. The observability config (scrape, dashboards, alerts).

## Checklist

- [ ] `helm template charts/ ...` renders cleanly (dry-run).
- [ ] No secrets in chart/values/images; images digest-pinned; chart version bumped.
- [ ] IRSA least-privilege; hostname/route non-conflicting.
- [ ] Wired into the existing monitoring stack — no new infra.
- [ ] Deploy + rollback plans complete; both are operator actions, never executed here.
