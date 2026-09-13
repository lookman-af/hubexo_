# Contoh IaC untuk assessment cloud platform

Status verifikasi: `terraform fmt` dan `terraform validate` berhasil dengan Terraform
1.15.8 dan AzureRM 4.43.0. Belum menjalankan plan/apply atau pengujian pada Azure.
Desain pipeline terdapat pada `pipeline.md`.

Contoh reusable Terraform Azure untuk satu aplikasi pada satu environment.
Root module memilih subscription/environment, child module membuat Resource Group,
VNet, managed identity, Key Vault, monitoring, dan Linux App Service.

## Struktur dan kontrol

- `terraform/main.tf`: provider, remote backend, validasi environment, metadata, pemanggilan modul.
- `terraform/modules/web-platform/main.tf`: workload module tanpa credential/provider configuration.
- `terraform/dev.tfvars.example`: input contoh; buat input terpisah untuk dev, test, staging, prod.
- Satu invocation/state per aplikasi/environment, jangan membuat seluruh 30 tim dalam satu state.
- Subscription berbeda per environment/product boundary; CIDR dialokasikan terpusat dan tidak overlap.
- App Service dan Key Vault mematikan public network access; masing-masing memiliki private endpoint dan DNS.
- App Service outbound VNet integration menggunakan subnet terpisah dari private endpoints.
- Aplikasi memakai managed identity dengan role Key Vault Secrets User hanya pada vault miliknya.
- Tidak ada secret value yang dibuat, dibaca, atau dikeluarkan melalui Terraform.
- Staging/prod memakai tiga worker dan zone balancing. Validasi dukungan region/SKU dan quota sebelum deployment.
- Provider dipin untuk reproducibility contoh, bukan klaim bahwa versi itu paling baru. Upgrade melalui PR dan validasi.

## Prasyarat integrasi production

Contoh ini bukan landing zone production lengkap. Platform layer perlu menyediakan:

1. Remote backend Azure Storage terpisah untuk prod/nonprod, Entra/OIDC authentication,
   private access, versioning, access controls, dan blob lease locking. Bootstrap backend
   di luar state workload ini. Jangan mengandalkan workspace atau nama state sebagai isolation boundary.
2. Identity provisioning khusus dengan izin resource-group creation dan role-assignment
   yang dibatasi; identity application deployment tidak mendapat izin membuat role assignment.
3. Private runner serta konektivitas dan DNS ke app/SCM endpoints untuk deployment.
4. Regional hub, peering, NSG, UDR, Firewall dan egress allowlist. VNet integration pada
   contoh ini tidak otomatis memaksa semua outbound melalui firewall.
5. Central private DNS/resolver. Ganti zone contoh dengan referensi zone yang dikelola platform.
6. WAF/global ingress dengan private origin connectivity untuk aplikasi publik.
7. Azure Policy, security monitoring/SIEM, immutable audit archive, alerts dan action groups.
8. Autoscaling yang sudah diuji, backup/restore untuk data, serta secondary region sesuai RTO/RPO.
9. Application package, authentication/authorization aplikasi, endpoint `/health/ready`, dan
   OpenTelemetry SDK/exporter. Connection string App Insights saja tidak menginstrumentasi aplikasi.
10. Deployment slots beserta identity, private endpoints/DNS dan konfigurasi per slot jika memakai swap.
    Slot kandidat di production tidak menggantikan environment staging yang terisolasi.

App Service tidak scale-to-zero; menghentikan app tidak menghentikan biaya plan.
Untuk ephemeral workloads, gunakan modul Container Apps/jobs atau hapus compute nonprod
yang memang boleh dihapus. Purge protection vault dapat menghambat reuse nama setelah deletion.

## Validasi lokal (tidak men-deploy)

```sh
cd terraform
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
```

Untuk deployment aktual, lakukan init ulang dengan backend milik organisasi dan OIDC.
Gunakan backend identity yang berbeda per boundary, `use_azuread_auth=true`, dan `use_oidc=true`.
Jangan memasukkan access key atau token ke file backend. Per-environment pipeline menghasilkan
plan yang di-review; apply hanya plan yang disetujui, dengan concurrency lock dan pemeriksaan drift.

Pemeriksaan cloud yang diperlukan: plan, Azure Policy evaluation, private DNS/app/SCM reachability,
Key Vault authorization positif/negatif, health endpoint, telemetry arrival, serta zonal/rollback tests.
Tidak ada resource Azure yang dibuat sebagai bagian dari penyusunan contoh assessment ini.

## Referensi

- https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/
- https://learn.microsoft.com/en-us/azure/app-service/networking/private-endpoint
- https://learn.microsoft.com/en-us/azure/app-service/overview-vnet-integration
- https://registry.terraform.io/providers/hashicorp/azurerm/4.43.0/docs/resources/linux_web_app
- https://registry.terraform.io/providers/hashicorp/azurerm/4.43.0/docs/resources/key_vault
