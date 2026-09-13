#!/usr/bin/env python3
"""Render exact Terraform Helm values with public fixtures; never access a cluster."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
terraform = shutil.which("terraform")
helm = shutil.which("helm")
if not terraform or not helm:
    raise SystemExit("terraform and helm must be on PATH")

source = (ROOT / "modules/vault-runtime/main.tf").read_text()
start = re.search(r"values\s*=\s*\[yamlencode\(", source).start()
start = source.index("yamlencode(", start)
end = source.index("})]", start) + 2
expression = source[start:end]
fixtures = {
    "var.region": '"eu-west-1"',
    "var.unseal_key_arn": '"arn:aws:kms:eu-west-1:111122223333:key/11111111-2222-3333-4444-555555555555"',
    "var.vault_role_arn": '"arn:aws:iam::111122223333:role/test-vault"',
    "var.vault_tls_secret_name": '"vault-server-tls"',
    "kubernetes_storage_class_v1.vault.metadata[0].name": '"vault-gp3-retain"',
}
for name, value in fixtures.items():
    expression = expression.replace(name, value)

with tempfile.TemporaryDirectory(prefix="vault-chart-check-") as scratch:
    path = Path(scratch)
    (path / "main.tf").write_text("locals {\n values = " + expression + "\n}\n")
    result = subprocess.run(
        [terraform, f"-chdir={scratch}", "console"],
        input="jsonencode(local.values)\n", text=True, capture_output=True, check=True,
    )
    values = json.loads(json.loads(result.stdout))
    (path / "values.yaml").write_text(values)
    kubeconfig = path / "kubeconfig"
    kubeconfig.write_text("apiVersion: v1\nkind: Config\nclusters: []\ncontexts: []\nusers: []\n")
    kubeconfig.chmod(0o600)
    env = dict(os.environ, KUBECONFIG=str(kubeconfig))
    result = subprocess.run([
        helm, "template", "vault", "vault", "--repo", "https://helm.releases.hashicorp.com",
        "--version", "0.34.1", "--namespace", "vault", "--kube-version", "1.35.0",
        "--values", str(path / "values.yaml"),
    ], text=True, capture_output=True, env=env, check=True)
    rendered = result.stdout
    (path / "documents.json").write_text(json.dumps(rendered.split("\n---")))
    decoded = subprocess.run(
        [terraform, f"-chdir={scratch}", "console"],
        input='jsonencode([for d in jsondecode(file("documents.json")) : yamldecode(d)])\n',
        text=True, capture_output=True, check=True,
    )
    documents = [d for d in json.loads(json.loads(decoded.stdout)) if d]
    server = next(d for d in documents if d["kind"] == "StatefulSet")
    injector = next(d for d in documents if d["kind"] == "Deployment")
    webhook = next(d for d in documents if d["kind"] == "MutatingWebhookConfiguration")
    assert server["spec"]["replicas"] == 3
    assert injector["spec"]["replicas"] == 2
    pod = server["spec"]["template"]["spec"]
    terms = pod["affinity"]["podAntiAffinity"]["requiredDuringSchedulingIgnoredDuringExecution"]
    assert any(t["topologyKey"] == "topology.kubernetes.io/zone" for t in terms)
    assert all(v["spec"]["storageClassName"] == "vault-gp3-retain"
               for v in server["spec"]["volumeClaimTemplates"])
    assert all(w["failurePolicy"] == "Fail" for w in webhook["webhooks"])
    assert all(w["namespaceSelector"]["matchLabels"]["vault-injection"] == "enabled"
               for w in webhook["webhooks"])
    vault_env = {e["name"]: e.get("value") for e in pod["containers"][0]["env"]}
    assert vault_env["VAULT_API_ADDR"] == "https://vault-active.vault.svc:8200"
    assert 'tls_min_version = "tls12"' in rendered
    assert 'seal "awskms"' in rendered and 'tls_disable = 1' not in rendered
    assert any(d["kind"] == "PodDisruptionBudget" and d["spec"].get("maxUnavailable") == 1
               for d in documents)
    if result.stderr.strip():
        raise SystemExit("Unexpected Helm warning: " + result.stderr)
    print("PASS: exact Vault chart values render with HA, AZ spread, TLS, service API address, retained storage, and fail-closed injection.")
