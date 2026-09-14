# Part 6 — Agentic AI Governance

[Requirements index](README.md) · [Repository home](../../README.md) · [Previous: FinOps](part-5-finops.md)

## Operating model

Agents may generate code, create PRs, propose infrastructure changes, and execute
approved operational tasks. An authenticated tool gateway checks each request against
policy; a separate executor performs permitted operations with scoped credentials.
The model proposes actions but cannot grant itself authority. This follows
[AWS guidance for secure agent access](https://docs.aws.amazon.com/prescriptive-guidance/latest/security-reference-architecture-generative-ai/gen-auto-agents.html).

## Identity — How are agents authenticated?

Register each agent with an owner, purpose, permitted environments, and lifecycle.
Assign a dedicated workload identity and a unique task/session ID. Authenticate EKS
runtimes with projected service-account tokens validated for issuer, audience, and
expiry; use EKS Pod Identity or IRSA when AWS credentials are required. Trusted CI
executors use constrained OIDC federation. Never use shared human credentials.

Keep the requester, agent, and executor identities distinct and linked in the task
record. Use short-lived repository installation tokens scoped to approved repositories.
Authenticate Vault access with a dedicated role and exact secret-path permissions.
Keep credentials in the execution layer, outside prompts and model context.

## Authorisation — What permissions should they have?

Default to deny. At every tool call, check the task, operation, resource, environment,
approval, and expiry. Effective authority is bounded by the requester's entitlement,
the agent's assigned scope, and the execution policy; an approved request cannot
expand the executor's underlying IAM, Kubernetes, or Vault permissions.

| Task | Allowed scope and boundary |
| --- | --- |
| Generate code and tests | Read approved repositories and write to an isolated workspace. Sandbox code execution; restrict network access and resource usage. |
| Create PRs | Push an agent branch and open a PR in named repositories. No direct protected-branch writes, approval bypass, or self-approval. |
| Propose infrastructure | Generate Terraform changes and request a trusted plan. Planning is privileged because providers and data sources execute code; inspect configuration before credentialed execution and protect plan/state contents. |
| Execute operations | Invoke versioned, allowlisted runbooks with validated parameters, target limits, timeout, concurrency limit, and retry budget. No arbitrary production shell or cluster-admin access. |

Block changes to IAM trust, RBAC, Vault policy, audit controls, and approval policy
through agent execution roles. Such proposals use a separate human-controlled workflow.
Treat repository text, retrieved documents, and tool output as untrusted data. Prompt
injection detection supplements deterministic authorization; it cannot replace it.

## Human oversight — When is approval required?

| Action | Approval rule |
| --- | --- |
| Generate code, run isolated tests, or open a PR | May proceed within the owner's pre-approved task scope. Required reviewers and checks still govern merging. |
| Low-risk nonproduction runbook | May execute under an explicitly approved automation policy with defined limits. |
| Production operation, destructive action, or material cost increase | Require explicit approval from the accountable service/platform owner before execution. |
| Access-policy changes, sensitive data export, or security exceptions | Require the designated security/data owner and a separate controlled execution path. Approval alone does not override a denied permission. |

Present the exact diff or plan, target, parameters, impact, and recovery procedure.
Bind approval to the artifact/runbook version, parameter hash, environment, and expiry.
Any material change requires renewed approval. The agent cannot approve its own work;
missing, expired, or unverifiable approval stops execution.

## Auditability — How is activity recorded?

Record requester, agent/task identity, executor identity, model/version, policy decision,
approver and approval reference, tool parameters after redaction, target, timestamps,
outcome, and PR/deployment links. Include denied and failed calls, token usage, and cost.
Correlate gateway records with repository/CI audit events, CloudTrail, EKS audit logs,
and Vault audit logs; CloudTrail alone does not cover all agent activity.

Forward records to security-owned, access-controlled storage with reviewed retention
and S3 Object Lock where required. Exclude secrets and private chain-of-thought;
minimize and redact stored prompt/tool content. For privileged tasks, fail closed if
the required approval or audit record cannot be durably recorded. See
[Observability](part-2-observability.md) for dashboards and alert routing.

## Emergency controls — How can an agent be suspended or isolated?

Provide a kill switch outside agent permissions, available to the on-call/security
team, that can target one task, an agent identity, or the fleet.

1. **Stop execution:** deny new gateway calls, cancel queued tasks and CI runs, and stop active executors. Block automatic retries and rescheduling.
2. **Cut access:** prevent new credential issuance, revoke repository tokens and Vault service tokens/leases, and deny affected AWS role sessions. Changing role trust alone does not invalidate existing STS credentials; use the documented session-revocation mechanism and verify its effect.
3. **Isolate:** quarantine the workload with enforced network/egress controls and remove target-system authorization. Do not rely only on deleting a pod or waiting for token expiry.
4. **Verify containment:** test that previously issued credentials cannot perform actions, inspect downstream jobs and changes, and rotate exposed static secrets. Vault revocation does not undo a copied KV secret; confirm dynamic credential revocation at the backing service too.
5. **Recover deliberately:** preserve evidence, assess impact, and obtain owner/security approval before restarting with fresh credentials and reviewed policy. Suspension does not reverse actions already completed.

AWS role-session revocation can affect other sessions using the same role, so use
dedicated agent roles and assess the containment scope. Follow
[AWS session revocation guidance](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_revoke-sessions.html)
and [Vault lease revocation guidance](https://developer.hashicorp.com/vault/docs/concepts/lease).

## Acceptance checks

Test cross-environment denial, prompt injection, stale approval, self-approval attempts,
secret exfiltration, and budget exhaustion. Rehearse the kill switch during an active
task, measure time to containment, and verify existing credentials and queued work
cannot continue. Record an owner and remediation for each failed control.

These are target governance controls. The tool gateway, approval service, agent
identities, and emergency automation are not provisioned by the current Terraform sample.
