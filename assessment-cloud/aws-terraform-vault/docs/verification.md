# Verification status and acceptance checks

## Local checks performed

- Terraform 1.15.8: recursive formatting and schema validation of all four stacks.
- Locked providers: AWS 6.64.0, Helm 2.17.0, Kubernetes 2.38.0, Vault 5.11.0.
- Official Vault chart 0.34.1, Vault 2.0.4, injector 1.7.6: local Helm manifest render.
- Three mocked Terraform test runs: production isolation, development cost boundary,
  and exact application Vault permission scope. All provider operations in these tests
  are mocked; their add-on version strings are fixtures, not deployment recommendations.
- Chart checks cover three server replicas, two injectors, AZ anti-affinity, gp3
  StorageClass reference, TLS configuration, advertised service address, disruption
  budget, namespace selector, and fail-closed admission behavior.

No AWS resources were created, no live Vault was initialized, and no Kubernetes
deployment was performed. Schema validation and mocked tests do not demonstrate live
service compatibility, IAM authorization, actual network reachability, or recovery.

## Reproduce local verification

From the package root, with Terraform and Helm on PATH:

```sh
terraform fmt -check -recursive
terraform -chdir=stacks/01-foundation init -backend=false
terraform -chdir=stacks/01-foundation validate
terraform -chdir=stacks/01-foundation test
terraform -chdir=stacks/02-vault-runtime init -backend=false
terraform -chdir=stacks/02-vault-runtime validate
terraform -chdir=stacks/03-vault-config init -backend=false
terraform -chdir=stacks/03-vault-config validate
terraform -chdir=stacks/03-vault-config test
terraform -chdir=stacks/04-application init -backend=false
terraform -chdir=stacks/04-application validate
python3 scripts/check_vault_chart.py
```

The chart checker substitutes only public fixture IDs into the actual Terraform
Helm-values expression. It uses a temporary directory and an empty kubeconfig; it
does not call a Kubernetes API. Downloads require access to official registries.

## Checks required before production acceptance

1. **Environment/account identity:** correct account allowlist, unique state paths,
   bounded deployer role trust, and no nonproduction principal with production access.
2. **EKS:** supported/add-on versions, three AZ node readiness, CNI enforcement, EBS
   volume provisioning, private API reachability, and intended IMDS restrictions.
3. **Vault bootstrap:** TLS/SAN verification without bypass, KMS role/key access,
   exactly one initialization, three Raft peers, one active leader and no sealed nodes.
4. **Authentication:** an approved pod reads only its exact configuration; wrong
   namespace, wrong service account, wrong JWT audience and another path are rejected.
5. **Secret handling:** init/sidecar injection succeeds under Pod Security Admission;
   secret values and Vault tokens do not appear in Terraform state, Git, logs or images.
   Rotate a test value and verify the application reloads its file without disclosure.
6. **Admission/network failure:** unavailable injector blocks labeled workload creation;
   unapproved ingress/egress fails; DNS and Vault remain reachable. Verify behavior of
   the selected CNI mode during policy initialization, not only steady state.
7. **Observability:** EKS logs arrive, Vault audit output is forwarded to protected
   storage, authenticated metrics are scraped, and a synthetic incident pages the owner.
8. **Recovery:** evict one voter safely, test one AZ failure, restore an encrypted
   Raft snapshot, and validate KMS/certificate dependencies against agreed RTO/RPO.
9. **Supply chain and capacity:** scan the pinned images/provider/chart versions,
   verify image signatures through platform policy, measure workload sizing and cost,
   and review private endpoints/egress inspection before processing sensitive data.

Complete integration tests in Dev/Test and Staging before authorizing Production.
