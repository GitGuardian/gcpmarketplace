#!/bin/bash
set -e

echo "=== GitGuardian Custom Deployer Wrapper ==="
echo "DEBUG: Wrapper is being executed"
echo "DEBUG: PATH=$PATH"
echo "DEBUG: Checking for prepare-gg-deployment.sh..."
ls -la /bin/prepare-gg-deployment.sh || echo "ERROR: prepare-gg-deployment.sh not found!"

# Process license file first (this sets environment variables)
if [ -f /bin/prepare-gg-deployment.sh ]; then
    echo "Processing Replicated license..."
    source /bin/prepare-gg-deployment.sh
else
    echo "ERROR: GitGuardian deployment preparation script not found!"
    exit 1
fi

echo "License processing and chart modification complete, starting deployment..."
echo ""

# Call the original deployer entrypoint (renamed to deploy_original.sh)
exec /bin/deploy_original.sh "$@"

