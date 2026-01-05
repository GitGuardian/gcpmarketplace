# Contributing / Local Development

This guide is for developers working on the GCP Marketplace deployer itself.

## Prerequisites

- Docker
- Valid Replicated license credentials

## Local Debugging

### 1. Create a test values file

Create a `test-values.yaml` file at the repository root.

> **⚠️ Required:** You MUST replace these two values with your Replicated credentials:
> - `replicatedLicenseId` - Your Replicated license ID
> - `gitguardian.onPrem.adminUser.email` - The email associated with your Replicated license (used for registry authentication)

```yaml
# GCP Marketplace uses flat keys with dots in the name (not nested YAML)

# ⚠️ REQUIRED: Replace with your Replicated credentials
replicatedLicenseId: "your-license-id-here"

# GCP Marketplace managed values
name: gitguardian
namespace: gitguardian
storageClass: standard

# GitGuardian configuration
gitguardian.hostname: gitguardian.example.com

# ⚠️ REQUIRED: Email associated with your Replicated license (used for registry login)
gitguardian.onPrem.adminUser.email: admin@example.com
gitguardian.onPrem.adminUser.password: "your-admin-password"
gitguardian.onPrem.adminUser.firstname: Admin

# PostgreSQL configuration (Cloud SQL)
gitguardian.postgresql.host: 127.0.0.1
gitguardian.postgresql.port: 5432
gitguardian.postgresql.username: gitguardian
gitguardian.postgresql.password: "your-postgres-password"
gitguardian.postgresql.database: gitguardian
gitguardian.postgresql.tls.mode: require

# Redis configuration (Memorystore)
gitguardian.redis.main.host: 127.0.0.1
gitguardian.redis.main.port: 6379
gitguardian.redis.main.password: ""
gitguardian.redis.main.user: ""

# Ingress configuration
gitguardian.ingress.enabled: true
gitguardian.ingress.tls.enabled: false
gitguardian.ingress.tls.existingSecret: ""

# Service accounts (GCP Marketplace managed)
gitguardian.serviceAccount.name: gitguardian-sa
gitguardian.migration.serviceAccount.name: gitguardian-migration-sa
gitguardian.replicated.serviceAccountName: gitguardian-replicated-sa
serviceAccount.name: gitguardian-sa
```

### 2. Build the Docker image

```bash
docker build -t gg-deployer .
```

### 3. Run the container interactively

Mount your test values file and start a bash shell:

```bash
docker run -it --rm \
  --entrypoint "" \
  -v $(pwd)/test-values.yaml:/data/values.yaml \
  gg-deployer \
  bash
```

> **Note:** The file is mounted to `/data/values.yaml` which is where GCP Marketplace stores deployment parameters.

### 4. Inside the container

Once inside the container, you can:

```bash
# Check the mounted values
cat /data/values.yaml

# Check the chart structure
ls -la /data/chart/

# Manually run the preparation script
source /bin/prepare-gg-deployment.sh
```

## Key Files

| File | Location in container | Description |
|------|----------------------|-------------|
| `prepare-gg-deployment.sh` | `/bin/prepare-gg-deployment.sh` | Main preparation script (license validation, subchart download, values merge) |
| `deployer-wrapper.sh` | `/bin/deploy.sh` | Entry point wrapper that calls preparation then original deployer |
| `gcp-values.yaml` | `/data/gcp-values.yaml` | GCP-specific default values merged into subchart |

## Debugging Tips

1. **Check yq is working:**
   ```bash
   yq --version
   yq eval '.replicatedLicenseId' /data/values.yaml
   ```

2. **Test license validation manually:**
   ```bash
   helm registry login registry.replicated.com \
     --username "your-email@example.com" \
     --password "your-license-id"
   ```

3. **Inspect the chart after preparation:**
   ```bash
   # After running prepare-gg-deployment.sh
   ls -la /data/chart/charts/
   cd /data/chart/charts/
   tar -xzf gitguardian-*.tgz
   cd gitguardian
   cat values.yaml | grep -A4 serviceAccount  # see the create is set to false as per gcp-values.yaml
   ```

## Deployer Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    GCP Marketplace                          │
│                         │                                   │
│                         ▼                                   │
│              ┌──────────────────────┐                       │
│              │   deploy.sh          │ (deployer-wrapper.sh) │
│              └──────────────────────┘                       │
│                         │                                   │
│                         ▼                                   │
│    ┌─────────────────────────────────────────────────┐     │
│    │        prepare-gg-deployment.sh                  │     │
│    │  1. Validate license with Replicated registry    │     │
│    │  2. Add gitguardian subchart dependency          │     │
│    │  3. Pull subchart from registry.replicated.com   │     │
│    │  4. Merge gcp-values.yaml into subchart          │     │
│    │  5. Re-package chart with subchart               │     │
│    └─────────────────────────────────────────────────┘     │
│                         │                                   │
│                         ▼                                   │
│              ┌─────────────────────┐                        │
│              │  deploy_original.sh │ (GCP Helm deployer)    │
│              └─────────────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

