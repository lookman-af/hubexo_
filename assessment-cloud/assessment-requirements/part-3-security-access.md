# Part 3 — Security & Access

[Requirements index](README.md) · [Repository home](../../README.md) · [Previous: Observability](part-2-observability.md) · [Next: Platform Engineering](part-4-platform-engineering.md)

## Access model

Use federated, short-lived identities and separate permissions by team, service, and
environment. Keep application access separate from platform administration.

| Area | Recommended approach |
| --- | --- |
| Human access | Federate the corporate identity provider through IAM Identity Center, enforce MFA, and assign group-based permission sets. Map approved IAM roles through EKS access entries to namespace-scoped access policies or Kubernetes RBAC. Remove access through the joiner/mover/leaver process and review membership regularly. |
| Service identity | Give each application a dedicated Kubernetes service account and, when AWS access is needed, its own IAM role. Use EKS Pod Identity where supported, or IRSA for the existing Terraform pattern. Scope access to required actions and resources; restrict node metadata access. Never share node credentials with applications. |
| Delivery identity | Use short-lived OIDC federation constrained to the approved repository, workflow, and environment. Separate plan, infrastructure apply, and application deployment roles. Untrusted PR execution receives no deployment credentials or private runner access. |
| Production access | Default humans to operational visibility without secret access. Deliver routine changes through protected automation; require independent approval for privileged or high-risk changes. Grant incident access just in time, with an expiry, incident reference, and recorded actions. |

EKS permissions must be evaluated together: a namespace-scoped grant does not cancel
another cluster-wide grant. Check both access entries and RBAC, and avoid standing
cluster-admin membership. These choices align with
[AWS EKS access guidance](https://docs.aws.amazon.com/eks/latest/best-practices/cluster-access-management.html)
and [workload identity guidance](https://docs.aws.amazon.com/eks/latest/userguide/service-accounts.html).

## Production safeguards

Use separate production accounts, state backends, Vault policies, and deployment
identities. Restrict access to private EKS endpoints through approved connectivity.
Treat pod creation and exec as privileged: either can expose workload credentials.
Product teams must not modify RBAC, admission controls, federation, or Vault policies
to grant themselves access. Apply SCPs and permission boundaries where appropriate;
these constrain permissions and do not grant them.

Maintain a separately protected emergency role for identity-provider or pipeline
failure. Alert on every use, require documented authorization, expire access promptly,
and review the incident afterward. Test the emergency path periodically.

## Secret management

Use HashiCorp Vault for application secrets. Authenticate pods with projected
Kubernetes tokens bound to the exact namespace, service account, and intended audience.
Return short-lived Vault tokens with a policy limited to the required secret path.
The authentication flow follows
[HashiCorp Kubernetes auth guidance](https://developer.hashicorp.com/vault/docs/auth/kubernetes).

- Inject secrets as files with Vault Agent; applications reload rotated values. Prefer dynamic, leased credentials where the backing service supports them; otherwise rotate KV secrets through an owned workflow.
- Keep secret values, private keys, recovery shares, and root tokens outside Git, Terraform configuration/state, images, and pipeline logs. Terraform manages policies and references only.
- Enable TLS verification and protected audit forwarding. Keep initialization and recovery custody under designated operators; revoke the initial root token after bootstrap.
- Use KMS auto-unseal and encrypted Raft storage with tested backups. Preserve quorum during maintenance and verify application behavior when Vault or KMS is unavailable.

The Terraform installer role currently receives cluster-admin for bootstrap; it is a
protected platform role, not the human or application access model described above.

## Acceptance checks

Verify offboarding and session expiry; deny cross-environment access and wrong
service-account/Vault-path requests. Rehearse approved incident access, secret rotation,
and credential revocation, and confirm all actions are attributable without logging
secret values.
