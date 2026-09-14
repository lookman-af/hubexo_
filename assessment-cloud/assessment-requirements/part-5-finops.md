# Part 5 — FinOps

[Requirements index](README.md) · [Repository home](../../README.md) · [Previous: Platform Engineering](part-4-platform-engineering.md)

## Scenario: costs rise 40% in three months

First establish whether growth comes from increased demand, higher cost per unit,
or a billing change. A 40% increase is a signal to investigate, not proof of waste.
Protect service SLOs while identifying the largest controllable drivers.

## Investigation approach

1. Confirm the comparison: equivalent periods, daily run rate, currency, account scope, and a consistent amortized cost basis. Separate credits, refunds, taxes, support, and one-off charges; review commitment expiry and coverage changes.
2. Use Cost Explorer to rank the absolute increase by service, account, region, environment, and owner. Reconcile the largest contributors to the total increase and correlate them with releases, migrations, traffic, and new workloads.
3. Use AWS Data Exports/CUR and Athena for detailed usage analysis. Enable EKS split cost allocation to attribute compute to workloads and identify idle capacity. Allocate shared network, observability, and platform costs using an agreed rule, without double counting.
4. Compare spend with successful requests, transactions, active customers, and completed AI tasks. Ask owners to explain the largest changes and distinguish necessary growth from idle resources, sizing issues, retries, or uncontrolled scaling.

EKS split cost allocation data is available through cost and usage reporting, not
Cost Explorer. See [AWS allocation guidance](https://docs.aws.amazon.com/cur/latest/userguide/enabling-split-cost-allocation-data.html).

## Metrics reviewed

| Area | Metrics and questions |
| --- | --- |
| Business efficiency | Daily cost, forecast, cost per successful transaction, traffic/customer growth, and allocation coverage. Is unit cost rising? |
| EKS compute | Node hours and rates, CPU/memory requests versus actual use, idle capacity, pending pods, HPA/Karpenter changes, and Spot/On-Demand mix. |
| Data and network | Storage growth, IOPS/throughput, snapshots, NAT processed bytes, cross-AZ/region transfer, and internet egress. |
| Observability | Log ingestion/retention, custom metric cardinality, trace volume, and duplicated collectors. |
| Commercial and AI | Commitment utilization/coverage, expired discounts, software charges, tokens per task, model mix, retries, and abandoned agent runs. |

Illustrative only: if cost rises from $100,000 to $140,000 while successful transactions
rise from 10 million to 15 million, unit cost falls from $0.0100 to about $0.0093.
The platform still needs a capacity and budget review, but efficiency has improved.

## Optimisation opportunities and risks

| Opportunity | Risk and safeguard |
| --- | --- |
| Remove confirmed idle resources and expire previews | Verify ownership, dependencies, and data retention before deletion; keep a recovery path. |
| Rightsize pods/nodes and schedule eligible nonproduction capacity | Test peak load and retain headroom. Avoid reducing Vault quorum, essential controllers, or production AZ resilience. |
| Use Spot for interruption-tolerant application capacity | Test interruption handling, diversify capacity, and retain stable capacity for critical services. |
| Reduce duplicate logs, excessive trace sampling, and unnecessary retention | Preserve audit evidence, detection coverage, and incident troubleshooting requirements. |
| Tune network paths, storage tiers, and database capacity | Compare total cost, including endpoint charges and retrieval/transfer fees; benchmark latency and recovery impact. |
| Buy commitments for a measured, stable usage floor | Rightsize first. Assess lock-in, utilization, and demand uncertainty before financial approval. |
| Bound AI task retries and model usage | Evaluate task quality and latency before changing models or budgets; stop repeated failed work through task controls. |

## Action plan and follow-up

Produce an owner-backed cost breakdown and a ranked backlog showing expected net
savings, effort, risk, rollback, and measurement period. Pilot reversible changes in
nonproduction, then canary production changes with SLO monitoring. Report realized
savings using the same cost basis and normalized demand; avoid adding overlapping
savings estimates.

Set AWS Budgets actual/forecast alerts and Cost Anomaly Detection notifications, and
review cost per service with owners regularly. These are monitoring controls, not
real-time spending caps. Use workload quotas and task limits for bounded execution;
do not automatically shut down production on a billing alert. Check coverage for
third-party and external AI charges separately. See
[AWS Cost Anomaly Detection](https://docs.aws.amazon.com/cost-management/latest/userguide/manage-ad.html).
