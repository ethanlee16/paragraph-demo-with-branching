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

    # Check if already processed
    if grep -q "$generator_func(" "$file_path"; then
        echo "    [i] File already processed with $generator_func. Skipping."
        return
    fi

    # Extract the original UUID from the readonly id property
    local original_uuid=""
    if grep -q "readonly id: string = " "$file_path"; then
        original_uuid=$(grep "readonly id: string = " "$file_path" | sed "s/.*readonly id: string = '\([^']*\)'.*/\1/")
    elif grep -q "readonly id = " "$file_path"; then
        original_uuid=$(grep "readonly id = " "$file_path" | sed "s/.*readonly id = '\([^']*\)'.*/\1/")
    fi

    # For resources, use name property or directory name as seed
    if [[ "$file_type" == "resource" ]]; then
        local resource_name=$(grep "name: string = " "$file_path" 2>/dev/null | sed "s/.*name: string = '\([^']*\)'.*/\1/" || true)
        if [[ -n "$resource_name" ]]; then
            seed_value="$resource_name"
            echo "    [i] Using name property as seed: $seed_value"
        else
            seed_value=$(basename "$(dirname "$file_path")")
            echo "    [i] Using directory name as seed: $seed_value"
        fi
    else
        seed_value="$original_uuid"
        echo "    [i] Using original UUID as seed: $seed_value"
    fi

    if [[ -z "$seed_value" ]]; then
        echo "    [!] Could not extract seed value from $file_name. Skipping."
        return
    fi

    # Add import if not present
    if ! grep -q "$generator_func" "$file_path"; then
        sed_inplace "1i\\
$import_path" "$file_path"
    fi

    # Update the readonly id property
    if grep -q "readonly id: string = " "$file_path"; then
        sed_inplace "s/readonly id: string = .*/readonly id: string = $generator_func('$seed_value');/" "$file_path"
    elif grep -q "readonly id = " "$file_path"; then
        sed_inplace "s/readonly id = .*/readonly id = $generator_func('$seed_value');/" "$file_path"
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