# Custom deployer that processes Replicated license file
#
# IMPORTANT: Version updates (Chart.yaml, values.yaml, schema.yaml) are done in CI
# BEFORE this build, not here. This is because the base image's ONBUILD triggers
# copy and package the chart BEFORE any of our Dockerfile commands run.
# See .github/workflows/build-images.yml for the version update step.
#
FROM gcr.io/cloud-marketplace-tools/k8s/deployer_helm/onbuild

# Install yq for YAML parsing (used at runtime by prepare-gg-deployment.sh)
RUN apt-get update && apt-get install -y wget && \
    ARCH=$(dpkg --print-architecture) && \
    wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH} -O /usr/bin/yq && \
    chmod +x /usr/bin/yq

# Copy chart, schema, and other files
COPY chart/gim /data/chart
COPY schema.yaml /data/
COPY builder/test/schema.yaml /data-test/
COPY builder/prepare-gg-deployment.sh /bin/prepare-gg-deployment.sh
COPY builder/gcp-values.yaml /data/gcp-values.yaml

RUN chmod +x /bin/prepare-gg-deployment.sh

# IMPORTANT: Replace deploy.sh AFTER any ONBUILD triggers have completed
# Backup original deployer
RUN if [ -f /bin/deploy.sh ]; then \
        mv /bin/deploy.sh /bin/deploy_original.sh; \
    fi

# Copy wrapper as the new deploy.sh (not a symlink!)
COPY builder/deployer-wrapper.sh /bin/deploy.sh
RUN chmod +x /bin/deploy.sh

ENV WAIT_FOR_READY_TIMEOUT=1800
