# GitGuardian for Google Cloud Marketplace

[![GCP Marketplace](https://img.shields.io/badge/GCP-Marketplace-4285F4?logo=google-cloud&logoColor=white)](https://console.cloud.google.com/marketplace)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.27+-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Helm](https://img.shields.io/badge/Helm-3.x-0F1689?logo=helm&logoColor=white)](https://helm.sh/)

Deploy GitGuardian Self-Hosted on Google Kubernetes Engine (GKE) through the Google Cloud Marketplace.

## Overview

[GitGuardian](https://www.gitguardian.com/) is the leading code security platform for secrets detection and code security. This repository contains the GCP Marketplace deployer wrapper for GitGuardian Self-Hosted, enabling one-click deployment on GKE clusters.

### Features

- 🔐 **Secrets Detection** - Detect hardcoded secrets in source code and CI/CD pipelines
- 🛡️ **Code Security** - Comprehensive security scanning for your codebase
- 📊 **Dashboard** - Centralized security dashboard for your organization
- 🔗 **Integrations** - Native integrations with GitHub, GitLab, Bitbucket, and more
- 📈 **Scalable** - Horizontally scalable architecture for enterprise workloads

## Architecture

```
┌──────────────────────────────────────────────────────────────-─┐
│                         Google Cloud                           │
│  ┌─────────────────────────────────────────────────────────-┐  │
│  │                       GKE Cluster                        │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │  │
│  │  │  Frontend   │  │   Workers   │  │    APIs     │       │  │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘       │  │
│  │         │                │                │              │  │
│  │         └────────────────┼────────────────┘              │  │
│  │                          │                               │  │
│  └──────────────────────────┼───────────────────────────────┘  │
│                             │                                  │
│  ┌──────────────────────────┼───────────────────────────────┐  │
│  │                  Managed Services                        │  │
│  │  ┌───────────────┐  ┌────┴────────┐                      │  │
│  │  │   Cloud SQL   │  │ Memorystore │                      │  │
│  │  │  (PostgreSQL) │  │   (Redis)   │                      │  │
│  │  └───────────────┘  └─────────────┘                      │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────-┘
```

For detailed architecture information, see the [GitGuardian Self-Hosted documentation](https://docs.gitguardian.com/self-hosting/home).

## Prerequisites

Before deploying GitGuardian, ensure you have:

See [Scaling documentation](https://docs.gitguardian.com/self-hosting/management/infrastructure-management/scaling#medium)

### 1. GKE Cluster

- GKE cluster running Kubernetes 1.32 or later

### 2. Cloud SQL for PostgreSQL

- PostgreSQL 16 or later

```bash
# Create database
gcloud sql databases create gitguardian --instance=YOUR_INSTANCE_NAME
```

### 3. Memorystore for Redis / Valkey

- Redis 6.x or later / Valkey 8.1 or later

### 4. GitGuardian License

- Valid GitGuardian Self-Hosted license
- License ID from your GitGuardian account
- Contact [support@gitguardian.com](mailto:support@gitguardian.com) to obtain a license

### 5. DNS and Ingress

- Domain name pointing to your cluster's ingress
- TLS certificate (optional but recommended)

## Quick Start

### Deploy via GCP Console

1. Go to [GitGuardian on GCP Marketplace](https://console.cloud.google.com/marketplace)
2. Click **Configure**
3. Select your GKE cluster and namespace
4. Fill in the required configuration:
   - **License ID**: Your GitGuardian license ID
   - **Admin Email**: Email for the initial admin user
   - **PostgreSQL Host**: Cloud SQL instance IP
   - **Redis Host**: Memorystore instance IP
   - **Hostname**: Your GitGuardian domain (e.g., `gitguardian.example.com`)
5. Click **Deploy**

## Configuration

### Required Parameters

| Parameter | Description |
|-----------|-------------|
| `License Id` | Your GitGuardian license ID |
| `Hostname` | Public hostname for GitGuardian |
| `Admin email` | Admin user email |
| `PostgreSQL Host` | PostgreSQL host (Cloud SQL IP) |
| `PostgreSQL Password` | PostgreSQL password |
| `Redis host` | Redis host (Memorystore IP) |

### Optional Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `PostgreSQL Port` | `5432` | PostgreSQL port |
| `PostgreSQL Database` | `gitguardian` | Database name |
| `PostgreSQL TLS Mode` | `require` | SSL mode (`disable`, `allow`, `prefer`, `require`) |
| `Redis port` | `6379` | Redis port |
| `Enable Ingress (Use loadbalancer)` | `true` | Enable Kubernetes Ingress |
| `Enable TLS for Ingress` | `false` | Enable TLS for Ingress |

## Verification

After deployment, verify the installation:

```bash
# Check application status
kubectl get applications -n $NAMESPACE

# Check all pods are running
kubectl get pods -n $NAMESPACE

# Check services
kubectl get svc -n $NAMESPACE

# View application logs
kubectl logs -l app.kubernetes.io/name=gitguardian -n $NAMESPACE --tail=100
```

### Access GitGuardian

1. Get the Ingress IP:
   ```bash
   kubectl get ingress -n $NAMESPACE
   ```

2. Configure your DNS to point to the Ingress IP

3. Access GitGuardian at `https://your-hostname`

4. Log in with the admin email and generated password:
   ```bash
   kubectl get secret -n $NAMESPACE -o jsonpath='{.data.admin-password}' | base64 -d
   ```

## Upgrading

### 1. Prepare Values File

Copy `docs/values-gcp.yaml` and replace all `REPLACE_ME` placeholders with your actual values.

### 2. Authenticate to Replicated Registry

```bash
helm registry login registry.replicated.com \
  --username YOUR_EMAIL \
  --password YOUR_LICENSE_ID
```

### 3. Generate Kubernetes Manifests

```bash
# Set variables
RELEASE_NAME=gitguardian
CHANNEL=stable                 # Or: beta, unstable
VERSION=0.1.9                  # Target version
NAMESPACE=gim

# Generate manifests
helm template $RELEASE_NAME \
  oci://registry.replicated.com/gitguardian/$CHANNEL/gitguardian \
  --version $VERSION \
  --namespace $NAMESPACE \
  -f values-gcp.yaml \
  > tpl.yaml
```

### 4. Delete Migration Jobs

Migration jobs are immutable and must be deleted before applying the new manifests:

```bash
kubectl delete job -n $NAMESPACE -l app.kubernetes.io/component=pre-deploy --ignore-not-found
kubectl delete job -n $NAMESPACE -l app.kubernetes.io/component=post-deploy --ignore-not-found
```

### 5. Apply Manifests

```bash
kubectl apply -f tpl.yaml --namespace $NAMESPACE
```

### 6. Verify Upgrade

```bash
# Check pods are running
kubectl get pods -n $NAMESPACE

# Watch migration jobs complete
kubectl get jobs -n $NAMESPACE -w
```

## Backup and Restore

### Database Backup

Use Cloud SQL automated backups or create manual backups:

```bash
gcloud sql backups create --instance=YOUR_INSTANCE_NAME
```

### Application Configuration

Export your configuration:
```bash
kubectl get configmap -n $NAMESPACE -o yaml > gitguardian-config-backup.yaml
kubectl get secret -n $NAMESPACE -o yaml > gitguardian-secrets-backup.yaml
```

## Uninstalling

### Via GCP Console

1. Go to **Kubernetes Engine** > **Applications**
2. Select your GitGuardian application
3. Click **Delete**

### Via Command Line

```bash
kubectl delete application $APP_NAME -n $NAMESPACE
kubectl delete namespace $NAMESPACE
```

> ⚠️ **Warning**: This will delete all GitGuardian resources. Ensure you have backed up your data before uninstalling.

## Troubleshooting

### Common Issues

#### Pods not starting

Check pod events:
```bash
kubectl describe pod -l app.kubernetes.io/name=gitguardian -n $NAMESPACE
```

#### Database connection issues

Verify Cloud SQL connectivity:
```bash
kubectl run pg-test --rm -it --image=postgres:14 --restart=Never -- \
  psql "host=YOUR_CLOUD_SQL_IP dbname=gitguardian user=gitguardian"
```

#### License validation failures

Verify your license ID is correct and active. Contact [support@gitguardian.com](mailto:support@gitguardian.com) if issues persist.

### Getting Help

- 📚 [GitGuardian Documentation](https://docs.gitguardian.com/)
- 💬 [GitGuardian Support](mailto:support@gitguardian.com)
- 🐛 [Report Issues](https://github.com/GitGuardian/gcpmarketplace/issues)

## Contributing

For local development and debugging of the deployer, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Support

For support inquiries:

- **Enterprise customers**: Contact your GitGuardian account manager or [support@gitguardian.com](mailto:support@gitguardian.com)
- **Documentation**: [docs.gitguardian.com](https://docs.gitguardian.com/)

## License

This deployer wrapper is provided under the [Apache License 2.0](LICENSE).

GitGuardian Self-Hosted requires a valid commercial license. Contact [support@gitguardian.com](mailto:support@gitguardian.com) for licensing information.

---

Made with ❤️ by [GitGuardian](https://www.gitguardian.com/)
