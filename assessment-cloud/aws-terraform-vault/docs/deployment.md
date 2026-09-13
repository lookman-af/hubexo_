# Deployment sequence and bootstrap boundaries

## Before deployment

Use an enrolled AWS account per product/environment and an approved private runner.
The AWS CLI executable must be on PATH because the Kubernetes and Helm providers use
`aws eks get-token`. Use federation/short-lived credentials, never committed keys.

Bootstrap an encrypted, versioned S3 state bucket separately. Block public access,
scope IAM to the required state objects and lock objects, and set `use_lockfile=true`.
Do not rely on state key names alone for production isolation. Use separate keys for
all four stages. The backend's region may differ from the workload's region.

Choose a supported EKS version and compatible, explicit add-on versions in the target
region. Replace example placeholders; do not assume a version shown in a sample is
the latest. Check node instance availability, IP capacity, service quotas, KMS policy,
and the deployer principal's ability to create/pass the narrowly scoped IAM roles.

Prepare a CA-issued Vault server certificate with SANs for the service names used:

- `vault.vault.svc` (the explicit TLS server name)
- `vault-active.vault.svc`
- `vault.vault.svc.cluster.local` and `vault-active.vault.svc.cluster.local`
- Pod DNS names under `vault-internal.vault.svc` if used without the explicit TLS name

The Secret must contain `tls.crt`, `tls.key`, and `ca.crt`. A PKI/bootstrap process
supplies it outside Terraform. Never use TLS skip-verify. Keep the CA/bootstrap
independent of the new Vault cluster to avoid a circular dependency.

## 1. AWS foundation

Initialize stack 01 using the environment's backend settings and run a reviewed
plan/apply with `examples/foundation.tfvars.example` adapted to the environment.
Save only its non-secret outputs as deployment metadata for stage 02. Avoid granting
downstream jobs read access to the entire foundation state just to obtain output IDs.

```sh
terraform -chdir=stacks/01-foundation init -backend-config=/secure/path/foundation.backend.hcl
terraform -chdir=stacks/01-foundation plan -var-file=/secure/path/foundation.tfvars -out=approved.tfplan
terraform -chdir=stacks/01-foundation apply approved.tfplan
terraform -chdir=stacks/01-foundation output -json platform
```

Plans can contain sensitive data. Protect and expire them. Apply the approved saved
plan only; re-plan/review when state or target changes. This sample has not executed
the plan/apply commands above against any cloud account.

The EKS endpoint is private. Establish the organization's private runner/VPN/TGW
route, security-group allowance and DNS path before stage 02. The sample does not
create a VPN or runner. Do not temporarily expose the EKS API as a bootstrap shortcut.

## 2. Install Vault runtime

Provide cluster name, unseal-key ARN, Vault IRSA role ARN, application namespace,
the public CA file and the server TLS Secret name. Stage 02 creates the namespaces,
public client trust bundle, encrypted Retain StorageClass and Helm release.

The Helm release intentionally uses `wait=false`: a new Vault cannot become ready
until it has its TLS Secret and is initialized. After the namespace exists, the
approved PKI process creates the TLS Secret in `vault`. Pods can remain Pending until
that happens. No private key is written through Terraform. Complete these bootstrap
steps before allowing any application promotion.

Confirm all three AZs have schedulable baseline capacity and the EBS CSI add-on is
healthy. Raft voters require distinct AZs. Confirm the injector webhook is healthy;
it is scoped to labeled application namespaces and fails closed there, preventing a
missing injector from silently starting an application without its secret files.

## 3. Controlled initialization, then Vault configuration

Initialize exactly one Raft node through a secure operator channel. Use recovery
shares and a threshold appropriate to the organization (for example 5 custodians,
threshold 3), with approved encryption/custody for recovery material and the initial
root token. Do not run initialization through Terraform `local-exec`, CI log output,
or an unprotected JSON output file. Other nodes join the initialized cluster using
the retry-join configuration and the shared auto-unseal key.

Auto-unseal uses the Vault service account's IRSA role and the dedicated KMS key.
Confirm all three peers have joined, one active node exists, and all are unsealed.
KMS availability/authorization remains a recovery dependency; protect the KMS key
and test loss-of-key-access scenarios. The key's Terraform `prevent_destroy` is not
a substitute for organizational deletion controls.

Use the initial root only to establish an approved administrative auth method and
scoped configuration identity, then revoke it. Stage 03 receives an externally issued,
short-lived `VAULT_TOKEN` through the trusted runner environment. Its provider uses
`skip_child_token=true`; the caller is responsible for the token lifetime and revocation.
Never pass the token as a Terraform variable. Configure `VAULT_ADDR`/the address input,
trusted CA and private DNS so the runner can reach the active Vault service.

The configuration identity needs only the necessary paths for the selected mounts,
auth backend, policies, audit device and self/version checks. Treat changes to audit,
auth and policy as privileged security changes requiring independent review. Stage 03
creates an exact-path read policy; applications cannot list other services or write
secrets. Its audience `vault` matches the projected token in stage 04.

Forward Vault audit stdout and server logs to the protected logging platform before
production acceptance. Configure authenticated scraping of `/v1/sys/metrics?format=prometheus`
using a separate identity with the `metrics-read` policy. Configure alerts for sealed
nodes, missing quorum/leader, unavailable storage, certificate expiry and audit failures.
The included metrics policy does not itself install a scraper or issue a credential.

## 4. Seed application secrets, then deploy

An authorized secret-management workflow populates the KV v2 path
`applications/<environment>/<application>/config`. The policy/API path includes
`applications/data/...`; Vault CLI KV commands use the logical path without `/data/`.
Supply values through a secure approved channel, not inline shell history or Terraform.

Stage 04 expects the namespace and public `vault-client-ca` trust bundle from stage 02.
Supply a scanned/signed immutable ECR image URI ending in `@sha256:<64 hex characters>`.
The application image must run as UID/GID 1000, listen on port 8080, support a read-only
root filesystem, expose `/health/ready` and `/health/live`, and read/reload JSON from
`CONFIG_FILE=/vault/secrets/config.json` without printing it. This is an application
contract; the sample does not bundle or falsely claim to build such an image.

Vault Agent injects an init container and renewing/rendering sidecar. The projected
Kubernetes token uses audience `vault` and is mounted into the agent, not intentionally
into the application container. Do not enable injection of the Vault token itself.
Test rotation and renewal, including behavior when Vault is temporarily unavailable.

The application has a private ClusterIP Service only. Same-namespace clients may
reach port 8080. Public ALB/WAF ingress is a separate platform integration and requires
an explicit NetworkPolicy/SG change. Do not assume the sample NetworkPolicy permits
ingress from an external load balancer. Add only approved application dependencies.

## Operating and decommissioning

- Keep Vault on dedicated platform capacity where isolation requires it; never grant
  application deployers permission to exec into Vault or read the server TLS key.
- Schedule encrypted Raft snapshots outside the cluster, with retention and restore
  drills. Copying a live EBS volume is not an application-consistent Raft backup.
- Vault chart updates use `OnDelete` for deliberate sequential server replacement.
  Update one voter at a time, verify quorum/readiness, and coordinate node-group
  upgrades one AZ at a time. A PDB cannot protect against arbitrary direct deletion.
- Three voters tolerate one unavailable voter; do not claim tolerance of two AZ losses.
- Retain PVs and verify backups before planned decommissioning. `prevent_destroy` on
  the seal key and Vault mount/audit resources requires explicit change review to
  remove. Namespace/PVC removal and loss of KMS access can still destroy availability.
- Review Vault edition/license/support and image vulnerabilities before release.
  Provider/chart locks improve reproducibility but do not replace patch management.
