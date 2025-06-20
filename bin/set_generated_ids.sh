#!/bin/bash
set -e

# Cross-platform sed function that works on both macOS and Linux
sed_inplace() {
    if sed --version 2>/dev/null | grep -q GNU; then
        # GNU sed (Linux/GitHub Actions)
        sed -i "$@"
    else
        # BSD sed (macOS)
        sed -i '' "$@"
    fi
}

# Generic function to update any file type
update_file() {
    local file_path="$1"
    local file_type="$2"
    local file_name=$(basename "$file_path")

    echo "Processing: $file_path"

    # Determine what to look for based on file type
    local extends_pattern=""
    local generator_func=""
    local import_path=""
    local seed_value=""

    case "$file_type" in
        "workflow")
            extends_pattern="extends Workflow"
            generator_func="generateWorkflowId"
            import_path="import { generateWorkflowId } from '../../../utils';"
            ;;
        "resource")
            extends_pattern="extends.*Resource"
            generator_func="generateResourceId"
            import_path="import { generateResourceId } from '../../utils';"
            ;;
        "trigger")
            extends_pattern="extends.*Trigger"
            generator_func="generateTriggerId"
            # Determine import path based on file location
            if [[ "$file_path" == *"/resources/"* ]]; then
                import_path="import { generateTriggerId } from '../../../utils';"
            else
                import_path="import { generateTriggerId } from '../../../../utils';"
            fi
            ;;
    esac

    # Check if file extends the expected class
    if ! grep -q "$extends_pattern" "$file_path"; then
        echo "    [.] File does not extend expected class. Skipping."
        return
    fi

    echo "    [?] Updating $file_type file: $file_name..."

    # Generate seed value based on file type and path
    if [[ "$file_type" == "workflow" ]]; then
        # Extract integration name and workflow file name from path
        # Expected path: ./src/integrations/{integrationName}/workflows/{workflowFile}.ts
        if [[ "$file_path" =~ ./src/integrations/([^/]+)/workflows/([^/]+)\.ts ]]; then
            local integration_name="${BASH_REMATCH[1]}"
            local workflow_file="${BASH_REMATCH[2]}"
            seed_value="${integration_name}/workflows/${workflow_file}.ts"
            echo "    [i] Using workflow path-based seed: $seed_value"
        else
            echo "    [!] Could not extract integration and workflow name from path: $file_path. Skipping."
            return
        fi
    elif [[ "$file_type" == "trigger" ]]; then
        # Extract integration/resource name and trigger file name from path
        # Expected paths: 
        # - ./src/integrations/{integrationName}/triggers/{triggerFile}.ts
        # - ./src/resources/{resourceName}/triggers/{triggerFile}.ts
        if [[ "$file_path" =~ ./src/(integrations|resources)/([^/]+)/triggers/([^/]+)\.ts ]]; then
            local parent_type="${BASH_REMATCH[1]}"
            local parent_name="${BASH_REMATCH[2]}"
            local trigger_file="${BASH_REMATCH[3]}"
            seed_value="${parent_name}/triggers/${trigger_file}.ts"
            echo "    [i] Using trigger path-based seed: $seed_value"
        else
            echo "    [!] Could not extract integration/resource and trigger name from path: $file_path. Skipping."
            return
        fi
    elif [[ "$file_type" == "resource" ]]; then
        # For resources, use name property or directory name as seed (unchanged)
        local resource_name=$(grep "name: string = " "$file_path" 2>/dev/null | sed "s/.*name: string = '\([^']*\)'.*/\1/" || true)
        if [[ -n "$resource_name" ]]; then
            seed_value="$resource_name"
            echo "    [i] Using name property as seed: $seed_value"
        else
            seed_value=$(basename "$(dirname "$file_path")")
            echo "    [i] Using directory name as seed: $seed_value"
        fi
    fi

    if [[ -z "$seed_value" ]]; then
        echo "    [!] Could not generate seed value for $file_name. Skipping."
        return
    fi

    # Add import if not present
    if ! grep -q "$generator_func" "$file_path"; then
        sed_inplace "1i\\
$import_path" "$file_path"
    fi

    # Update the readonly id property
    if grep -q "readonly id: string = " "$file_path"; then
        sed_inplace "s|readonly id: string = .*|readonly id: string = $generator_func('$seed_value');|" "$file_path"
    elif grep -q "readonly id = " "$file_path"; then
        sed_inplace "s|readonly id = .*|readonly id = $generator_func('$seed_value');|" "$file_path"
    fi

    echo "    [+] Success: $file_name!"
}

# Main execution
echo "Current directory: $(pwd)"

echo "=== Updating Workflows ==="
find ./src -path "*/workflows/*.ts" -type f | while read -r workflow; do
    update_file "$workflow" "workflow"
    echo
done

echo "=== Updating Resources ==="
find ./src/resources -name "config.ts" -type f | while read -r resource; do
    update_file "$resource" "resource"
    echo
done

echo "=== Updating Triggers ==="
find ./src -path "*/triggers/*.ts" -type f | while read -r trigger; do
    update_file "$trigger" "trigger"
    echo
done

echo "=== Complete ==="