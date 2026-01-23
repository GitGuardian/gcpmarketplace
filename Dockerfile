# Custom deployer that processes Replicated license file
FROM gcr.io/cloud-marketplace-tools/k8s/deployer_helm/onbuild

# Install yq for YAML parsing
RUN apt-get update && apt-get install -y wget && \
    ARCH=$(dpkg --print-architecture) && \
    wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH} -O /usr/bin/yq && \
    chmod +x /usr/bin/yq

# Accept version and channel as build args
ARG VERSION=0.0.0
ARG CHANNEL=stable

# Copy the chart
COPY chart/gim /data/chart

# Update version in Chart.yaml and channel in values.yaml
RUN yq eval ".version = \"${VERSION}\"" -i /data/chart/Chart.yaml && \
    yq eval ".channel = \"${CHANNEL}\"" -i /data/chart/values.yaml

# Copy the schema
COPY schema.yaml /data/
COPY builder/test/schema.yaml /data-test/

# Copy custom license processor
COPY builder/prepare-gg-deployment.sh /bin/prepare-gg-deployment.sh
RUN chmod +x /bin/prepare-gg-deployment.sh

# Copy GCP-specific default values (merged into subchart during deployment)
COPY builder/gcp-values.yaml /data/gcp-values.yaml

# IMPORTANT: Replace deploy.sh AFTER any ONBUILD triggers have completed
# Backup original deployer
RUN if [ -f /bin/deploy.sh ]; then \
        mv /bin/deploy.sh /bin/deploy_original.sh; \
    fi

# Copy wrapper as the new deploy.sh (not a symlink!)
COPY builder/deployer-wrapper.sh /bin/deploy.sh
RUN chmod +x /bin/deploy.sh

ENV WAIT_FOR_READY_TIMEOUT=1800
