#!/bin/bash
set -e

echo "=== GitGuardian Custom Deployer with License Validation ==="

# Check if yq is available
if ! command -v yq &> /dev/null; then
    echo "✗ ERROR: yq command not found!"
    echo "  yq is required for license processing"
    exit 1
fi

echo "✓ yq found at: $(which yq)"

# Read license from /data/values.yaml (where GCP Marketplace stores parameters)
if [ -f /data/values.yaml ]; then
    echo "Reading license from /data/values.yaml..."
    LICENSE_ID=$(yq eval '.replicatedLicenseId' /data/values.yaml 2>&1)
    CUSTOMER_EMAIL=$(yq eval '.["gitguardian.onPrem.adminUser.email"]' /data/values.yaml 2>&1)
    CHANNEL=$(yq eval '.channel' /data/chart/values.yaml 2>&1)
    # Set VERSION based on CHANNEL
    if [ "$CHANNEL" = "stable" ]; then
        VERSION=$(yq eval '.version' /data/chart/Chart.yaml 2>&1)
    else
        VERSION=">=0.0.0"
    fi
else
    echo "ERROR: /data/values.yaml not found"
fi

# Validate that we have required license information (from extracted variables)
if [ -z "$LICENSE_ID" ] || [ "$LICENSE_ID" = "null" ] \
    || [ -z "$CUSTOMER_EMAIL" ] || [ "$CUSTOMER_EMAIL" = "null" ] \
    || [ -z "$CHANNEL" ] || [ "$CHANNEL" = "null" ] \
    || [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then

    echo "WARNING: Failed to extract required values (email=$CUSTOMER_EMAIL, license=$LICENSE_ID, channel=$CHANNEL, version=$VERSION)"
    echo "Deploying wrapper"
else
    # Validate license by attempting to login to Replicated registry
    echo "Validating license with Replicated registry..."
    echo "  Registry: registry.replicated.com"
    echo "  Username: ${CUSTOMER_EMAIL}"
    echo "  License ID: HIDDEN"
    echo "  Attempting registry login..."

    # Attempt to login to Replicated registry using customer email and license ID
    # This validates that the license is active and valid
    # Add timeout to prevent hanging on invalid credentials
    # The wrapper will pass through 'registry login' to the real helm binary
    set +e  # Don't exit on error
    LOGIN_OUTPUT=$(timeout 30 helm registry login registry.replicated.com \
        --username "${CUSTOMER_EMAIL}" \
        --password "${LICENSE_ID}" 2>&1)
    LOGIN_EXIT_CODE=$?
    set -e  # Re-enable exit on error

    echo "  Login command completed with exit code: $LOGIN_EXIT_CODE"

    # Check if timeout occurred
    if [ $LOGIN_EXIT_CODE -eq 124 ]; then
        echo "✗ ERROR: License validation timed out after 30 seconds"
        echo "  This usually indicates network issues or invalid credentials"
        echo "  License ID: HIDDEN"
        echo "  Customer Email: ${CUSTOMER_EMAIL}"
        exit 1
    fi

    if [ $LOGIN_EXIT_CODE -eq 0 ]; then
        echo "✓ License validation successful - Helm registry login succeeded"
        echo "  License is valid and active in Replicated system"

        # Include the subchart
        echo "Adding gitguardian subchart dependency..."
        yq -i '.dependencies = (.dependencies // []) | .dependencies += [{"name": "gitguardian", "version": "'"$VERSION"'", "repository": "oci://registry.replicated.com/gitguardian/'"$CHANNEL"'"}]' /data/chart/Chart.yaml

        # Verify the Chart.yaml was modified correctly
        if ! yq e '.dependencies[] | select(.name == "gitguardian")' /data/chart/Chart.yaml > /dev/null 2>&1; then
            echo "✗ ERROR: Failed to add gitguardian dependency to Chart.yaml"
            exit 1
        fi
        echo "✓ Dependency added to Chart.yaml"

        # Pull the subchart
        echo "Pulling gitguardian subchart..."
        helm dependency update /data/chart/

        # Verify the subchart was downloaded
        if [ ! -f /data/chart/charts/gitguardian-*.tgz ]; then
            echo "✗ ERROR: Failed to download gitguardian subchart"
            ls -la /data/chart/charts/ || echo "charts/ directory doesn't exist or is empty"
            exit 1
        fi
        echo "✓ Subchart downloaded successfully"

        # Merge GCP-specific default values into the subchart
        # These values disable ServiceAccount/RBAC creation since GCP Marketplace manages them
        if [ -f /data/gcp-values.yaml ]; then
            echo "Merging GCP default values into subchart..."
            echo "  GCP values to merge (full file):"
            cat /data/gcp-values.yaml

            SUBCHART_TGZ=$(ls /data/chart/charts/gitguardian-*.tgz)
            SUBCHART_DIR="/tmp/subchart-extract"

            # Extract subchart
            mkdir -p "$SUBCHART_DIR"
            tar -xzf "$SUBCHART_TGZ" -C "$SUBCHART_DIR"

            # Find the extracted chart directory (gitguardian/)
            EXTRACTED_CHART=$(ls -d "$SUBCHART_DIR"/*/)
            echo "  Extracted to: $EXTRACTED_CHART"

            # Merge GCP values into subchart's values.yaml (GCP values take precedence)
            # Using ireduce for reliable deep merge
            yq eval-all '. as $item ireduce ({}; . * $item)' \
                "${EXTRACTED_CHART}values.yaml" /data/gcp-values.yaml \
                > "${EXTRACTED_CHART}values.yaml.merged"
            mv "${EXTRACTED_CHART}values.yaml.merged" "${EXTRACTED_CHART}values.yaml"

            # Show merged values.yaml
            echo "  Merged values.yaml:"
            cat "${EXTRACTED_CHART}values.yaml"

            # Re-package the subchart
            rm "$SUBCHART_TGZ"
            helm package "$EXTRACTED_CHART" --destination /data/chart/charts/

            # Cleanup
            rm -rf "$SUBCHART_DIR"

            echo "✓ GCP default values merged into subchart"
        else
            echo "WARNING: /data/gcp-values.yaml not found, skipping GCP defaults merge"
        fi

        # CRITICAL: Re-package the chart so the deployer uses the modified version
        # The ONBUILD trigger packaged the chart BEFORE our modifications,
        # so we need to replace chart.tar.gz with the updated chart
        echo "Re-packaging chart with subchart included..."

        # Remove the old pre-packaged chart
        rm -f /data/chart/chart.tar.gz

        # The deployer expects the tarball to have "chart/" as the root directory
        # (not the chart name like helm package creates)
        # So we manually create the tarball with the correct structure
        mkdir -p /tmp/repackage
        cp -r /data/chart /tmp/repackage/chart

        # Create tarball with "chart/" as root directory
        tar -czf /data/chart/chart.tar.gz -C /tmp/repackage chart

        # Cleanup
        rm -rf /tmp/repackage

        # Verify the new package exists
        if [ ! -f /data/chart/chart.tar.gz ]; then
            echo "✗ ERROR: Failed to re-package chart"
            exit 1
        fi
        echo "✓ Chart re-packaged successfully with subchart included"

        # Debug: Show what's in the package
        echo "  Package contents:"
        tar -tzf /data/chart/chart.tar.gz | head -20

    else
        echo "ERROR: Unable to authenticate to registry"
        echo "Deploying wrapper"
    fi

fi
