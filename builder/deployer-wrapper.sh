#!/bin/bash
set -e

echo "=== GitGuardian Custom Deployer Wrapper ==="
echo "DEBUG: Wrapper is being executed"
echo "DEBUG: PATH=$PATH"
echo "DEBUG: Checking for process_license.sh..."
ls -la /bin/process_license.sh || echo "ERROR: process_license.sh not found!"

# Process license file first (this sets environment variables)
if [ -f /bin/process_license.sh ]; then
    echo "Processing Replicated license..."
    source /bin/process_license.sh
else
    echo "ERROR: License processor script not found!"
    exit 1
fi

echo "License processing complete, starting deployment..."
echo ""

# Call the original deployer entrypoint (renamed to deploy_original.sh)
exec /bin/deploy_original.sh "$@"

