#!/bin/bash
base_dir="/home/podman/containers"

# Function to check if ranger-fm is installed
check_ranger_installed() {
    if ! command -v ranger &> /dev/null; then
        echo "ranger-fm is not installed. Would you like to install it now?"
        read -p "Install ranger-fm? (y/n): " install_ranger
        if [[ "$install_ranger" =~ ^[Yy]$ ]]; then
            sudo apt-get update && sudo apt-get upgrade -y
            sudo apt-get install -y ranger
            # Create config directory if it doesn't exist
            mkdir -p /home/podman/.config/ranger
            echo "ranger-fm installed successfully."
        else
            echo "ranger-fm is required for this feature. Please install it manually."
            return 1
        fi
    fi
    return 0
}

# Function to explain ranger-fm usage
explain_ranger_usage() {
    echo "ranger-fm Usage Guide:"
    echo "1. Navigation:"
    echo "   - Use arrow keys to move between files and directories"
    echo "   - Press 'Enter' to open a file or directory"
    echo "   - Press 'Backspace' to go up one directory level"

    echo "2. File Operations:"
    echo "   - Create new file: Press 'c' then 'f'"
    echo "   - Create new directory: Press 'c' then 'd'"
    echo "   - Edit file: Press 'e'"
    echo "   - Delete file: Press 'd'"
    echo "   - Rename file: Press 'r'"

    echo "3. Quitting:"
    echo "   - Press 'q' to quit ranger-fm"
    echo "   - Press 'Q' to quit and save current directory"

    read -p "Press Enter to continue..."
}

# Function to edit container files with ranger-fm
edit_container_files() {
    local container_name=$1

    # Check if ranger is installed
    if ! check_ranger_installed; then
        return 1
    fi

    # Explain ranger usage
    explain_ranger_usage

    # Open ranger in the container's directory
    echo "Opening ranger-fm for container $container_name..."
    ranger "$base_dir/$container_name"

    echo "File editing completed for container $container_name."
}

# Function to decompose a container (stop and remove containers)
decompose_container() {
    local container_name=$1

    # Ensure container is running before updating rootless_user
    if ! wait_for_container_running "$container_name"; then
        echo "Error: Container $container_name is not running. Cannot update rootless_user."
        return 1
    fi

    # Update rootless_user before decomposing
    update_rootless_user "$container_name"

    echo "Decomposing container $container_name..."
    podman-compose --file "$base_dir/$container_name/compose.yaml" down
    echo "Container $container_name decomposed successfully."
}

# Function to compose a container (start containers)
compose_container() {
    local container_name=$1
    echo "Composing container $container_name..."
    reapply_permissions "$container_name"
    podman-compose --file "$base_dir/$container_name/compose.yaml" up --detach

    # Wait for container to be fully running
    if ! wait_for_container_running "$container_name"; then
        echo "Error: Container $container_name did not start properly."
        return 1
    fi

    echo "Container $container_name composed successfully."
}

# Function to wait for container to be fully running with retries
wait_for_container_running() {
    local container_name=$1
    local max_attempts=60
    local attempt=0
    local status
    local health_status

    echo "Waiting for container $container_name to be fully running..."

    while [ $attempt -lt $max_attempts ]; do
        # Get container status
        status=$(podman inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null)

        if [ "$status" = "running" ]; then
            # Check if the container has a health check
            health_status=$(podman inspect -f '{{.State.Health.Status}}' "$container_name" 2>/dev/null)

            if [ -n "$health_status" ] && [ "$health_status" != "healthy" ]; then
                echo "Container $container_name is running but health check is $health_status..."
            else
                echo "Container $container_name is running and healthy."
                return 0
            fi
        elif [ "$status" = "exited" ] || [ "$status" = "dead" ]; then
            echo "Container $container_name is in $status state."
            exit_code=$(podman inspect -f '{{.State.ExitCode}}' "$container_name" 2>/dev/null)

            if [ -n "$exit_code" ] && [ "$exit_code" -ne 0 ]; then
                echo "Container exited with code $exit_code"
                echo "Container logs:"
                podman logs "$container_name" 2>&1
            fi
            return 1
        fi

        attempt=$((attempt + 1))
        sleep 2
    done

    echo "Timeout waiting for container $container_name to start."
    echo "Current status: $status"
    echo "Container logs:"
    podman logs "$container_name" 2>&1
    return 1
}

# Function to update rootless_user in .env with retries
update_rootless_user() {
    local container_name=$1
    local env_file="$base_dir/$container_name/.env"
    local max_retries=5
    local retry_count=0

    # Ensure container is running before updating rootless_user
    if ! wait_for_container_running "$container_name"; then
        echo "Error: Container $container_name is not running. Cannot update rootless_user."
        return 1
    fi

    while [ $retry_count -lt $max_retries ]; do
        # Get HUSER for user "abc"
        local podman_huser
        podman_huser=$(podman top "$container_name" user huser 2>/dev/null | awk 'NR>1 && $1=="abc" {print $2; exit}')

        if [ -n "$podman_huser" ]; then
            if [ -e "$env_file" ]; then
                # Check if file is writable
                if [ ! -w "$env_file" ]; then
                    sudo chmod u+w "$env_file"
                fi

                if grep -qE '^[[:space:]]*rootless_user=' "$env_file"; then
                    # Update existing key
                    sudo sed -i -E "s|^[[:space:]]*rootless_user=.*|rootless_user=$podman_huser|" "$env_file"
                else
                    # Append the key
                    sudo sh -c "printf '\nrootless_user=%s\n' '$podman_huser' >> '$env_file'"
                fi

                # Restore original permissions
                if [ ! -w "$env_file" ]; then
                    sudo chmod u-w "$env_file"
                fi
            else
                # Create new file with the key
                sudo sh -c "printf 'rootless_user=%s\n' '$podman_huser' > '$env_file'"
            fi

            echo "Updated rootless_user in .env"
            return 0
        else
            retry_count=$((retry_count + 1))
            echo "Attempt $retry_count: Could not determine HUSER for user 'abc' in container '$container_name'. Retrying in 5 seconds..."
            sleep 5
        fi
    done

    echo "Failed to update rootless_user after $max_retries attempts."
    return 1
}

# Function to display a styled menu
display_menu() {
    clear
    echo "============================================"
    echo "   PODMAN CONTAINER MANAGEMENT SYSTEM"
    echo "============================================"
    echo ""
    echo "1. List all containers"
    echo "2. Start a container"
    echo "3. Stop a container"
    echo "4. Create a new container"
    echo "5. Compose a container"
    echo "6. Decompose a container"
    echo "7. Edit container files"
    echo "8. Recompose a container"
    echo "99. Remove a container"
    echo "0. Exit"
    echo ""
    echo "============================================"
}

# Main menu
while true; do
    display_menu
    read -p "Enter your choice (0-99): " choice

    case $choice in
        1)
            list_containers
            read -p "Press Enter to continue..."
            ;;
        2)
            read -p "Enter the container name to start: " container_name
            start_container "$container_name"
            read -p "Press Enter to continue..."
            ;;
        3)
            read -p "Enter the container name to stop: " container_name
            stop_container "$container_name"
            read -p "Press Enter to continue..."
            ;;
        4)
            read -p "Enter the new container name: " container_name
            create_container "$container_name"
            read -p "Press Enter to continue..."
            ;;
        5)
            read -p "Enter the container name to compose: " container_name
            compose_container "$container_name"
            read -p "Press Enter to continue..."
            ;;
        6)
            read -p "Enter the container name to decompose: " container_name
            decompose_container "$container_name"
            read -p "Press Enter to continue..."
            ;;
        7)
            read -p "Enter the container name to edit files: " container_name
            edit_container_files "$container_name"
            read -p "Press Enter to continue..."
            ;;
        8)
            read -p "Enter the container name to recompose: " container_name
            decompose_container "$container_name" && compose_container "$container_name"
            read -p "Press Enter to continue..."
            ;;
        99)
            read -p "Enter the container name to remove: " container_name
            remove_container "$container_name"
            read -p "Press Enter to continue..."
            ;;
        0)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid choice. Please enter a number between 0 and 99."
            read -p "Press Enter to continue..."
            ;;
    esac
done
