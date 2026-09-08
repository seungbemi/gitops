# Hermes routing adjustment runbook

## Current policy

The admin agent sends `openrouter/auto` requests through policy middleware:

- cost tier: `medium`
- allowed models: the exact IDs under `model.routing.allowedModels`
- provider policy: all request parameters required, data collection denied
- price ceilings: $3/M prompt tokens and $15/M completion tokens
- fallback: `openai/gpt-5.6-luna`
- daily cost alert: $5

The allowlist is deliberately exact. Review a new model with the evaluation
suite before adding it; never replace exact IDs with provider-family wildcards.

## Data collected

The plugin and policy gateway record selected model/provider, Auto Router task
type when supplied, cost tier, candidate count, attempts, pipeline stages,
tokens, estimated or provider-reported cost, latency, fallback, platform, and
outcome. They do not export prompts, responses, tool arguments, session IDs, or
account identifiers. Cache hits may omit router metadata by OpenRouter design.

## Weekly review

Review at least seven complete days and at least 100 successful routed requests.
Split the Grafana results by task type, selected model, platform, and cost tier.
Compare them with the preceding fixed-Luna period.

Keep the policy when all of these hold:

- cost per successful task is at least 20% lower
- task success/evaluation score is no more than two percentage points lower
- p95 latency is no more than 20% higher
- provider/router fallback rate stays below 5%
- approval and external-action safety remains 100%
- router metadata is present on at least 90% of non-cached Auto Router calls

## Adjustment order

Change one dimension per review window so its effect remains measurable.

1. If quality is low, inspect failures by task type and model. Remove an
   underperforming model before raising the global cost tier.
2. If several models fail the same complex task types, raise `costTier` one
   level for the next canary window.
3. If cost is high but quality is healthy, lower price ceilings gradually.
   A ceiling is a hard filter; confirm eligible providers exist before rollout.
4. If latency or availability degrades, keep explicit `sort` unset so
   OpenRouter can route around unhealthy providers.
5. Add a model only after three evaluation runs pass and a seven-day canary
   meets the thresholds above.

Roll back to fixed Luna by setting `model.routing.enabled: false`. This also
turns off request-policy injection while retaining telemetry for fixed-model
comparison.

## PromQL checks

```promql
sum(increase(hermes_llm_cost_usd_total{routing_mode="auto"}[7d]))
/
sum(increase(hermes_telemetry_events_total{event_type="session_end",outcome=~"success|completed"}[7d]))
```

```promql
sum by (router_task_type, response_model) (
  increase(hermes_llm_router_decisions_total[7d])
)
```

```promql
histogram_quantile(0.95,
  sum by (le, response_model) (
    rate(hermes_llm_request_duration_seconds_bucket{routing_mode="auto"}[7d])
  )
)
```

```promql
sum(increase(hermes_llm_router_decisions_total{metadata_available="false"}[7d]))
/
sum(increase(hermes_llm_router_decisions_total[7d]))
```
