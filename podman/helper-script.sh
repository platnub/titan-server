#!/bin/bash

base_dir="/home/podman/containers"
rootless_user=""

# Function to display a message and wait for user confirmation
confirm_action() {
    local message=$1
    echo "$message"
    read -p "Continue? (y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to display a message and wait for user input
prompt_user() {
    local message=$1
    local default_value=$2
    read -p "$message [$default_value]: " user_input
    if [[ -z "$user_input" ]]; then
        echo "$default_value"
    else
        echo "$user_input"
    fi
}

# Function to display a message and wait for user confirmation with a summary
confirm_with_summary() {
    local message=$1
    local summary=$2
    echo "$message"
    echo "Summary:"
    echo "$summary"
    read -p "Continue? (y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to list all containers
list_containers() {
    echo "Listing all Podman containers:"
    podman ps -a
}

# Function to wait for container to be fully running
wait_for_container_running() {
    local container_name=$1
    local max_attempts=60  # Increased timeout
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
                # If there's a health check but it's not healthy yet
                echo "Container $container_name is running but health check is $health_status..."
            else
                # Either no health check or it's healthy
                echo "Container $container_name is running and healthy."
                return 0
            fi
        elif [ "$status" = "exited" ] || [ "$status" = "dead" ]; then
            echo "Container $container_name is in $status state."
            # Get exit code for more detailed error
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

# Function to run a container
start_container() {
    local container_name=$1
    reapply_permissions "$container_name"
    # Start the container
    echo "Starting container $container_name..."
    podman start "$container_name"
    # Wait for the container to be fully running
    if ! wait_for_container_running "$container_name"; then
        echo "Error: Container $container_name did not start properly."
        # Check container logs for errors
        echo "Container logs:"
        podman logs "$container_name" 2>&1
        # Try to restart the container if it failed
        echo "Attempting to restart container $container_name..."
        podman restart "$container_name"
        # Wait again
        if ! wait_for_container_running "$container_name"; then
            echo "Error: Container $container_name failed to start after restart."
            return 1
        fi
    fi
    update_rootless_user "$container_name"
    echo "Container $container_name started successfully."
}

# Function to stop a container
stop_container() {
    local container_name=$1
    # Only update .env if this was called from option 3 in the menu
    if [[ "$choice" == "3" ]]; then
        update_rootless_user "$container_name"
    fi
    podman stop "$container_name"
    echo "Container $container_name stopped successfully."
}

# Function to create new folders in appdata
create_appdata_folders() {
    local container_name=$1
    local appdata_dir="$base_dir/$container_name/appdata"
    echo "Checking for new folders to create in $appdata_dir..."
    while true; do
        read -p "Enter a folder name to create in appdata (leave empty to finish): " folder_name
        if [[ -z "$folder_name" ]]; then
            break
        fi
        # Create the folder
        sudo mkdir -p "$appdata_dir/$folder_name"
        echo "Created folder: $appdata_dir/$folder_name"
        # Apply permissions
        sudo chmod 700 "$appdata_dir/$folder_name"
        # If rootless_user is set, apply it
        if [ -n "$rootless_user" ]; then
            podman unshare chown "$rootless_user:$rootless_user" "$appdata_dir/$folder_name"
        fi
    done
}

# Function to decompose a container (stop and remove containers)
decompose_container() {
    local container_name=$1
    echo "Decomposing container $container_name..."
    podman-compose --file "$base_dir/$container_name/compose.yaml" down
    echo "Container $container_name decomposed successfully."
}

# Function to compose a container (start containers)
compose_container() {
    local container_name=$1
    echo "Composing container $container_name..."
    update_rootless_user "$container_name"
    reapply_permissions "$container_name"
    podman-compose --file "$base_dir/$container_name/compose.yaml" up --detach
    echo "Container $container_name composed successfully."
}

# Function to recompose a container (decompose and then compose)
recompose_container() {
    local container_name=$1
    decompose_container "$container_name"
    compose_container "$container_name"
}

# Function to create a new container
create_container() {
    local container_name=$1
    # Create container directories
    sudo mkdir -p "$base_dir/$container_name"
    sudo mkdir -p "$base_dir/$container_name/appdata"
    sudo mkdir -p "$base_dir/$container_name/logs"
    sudo mkdir -p "$base_dir/$container_name/secrets"
    # Create compose.yaml
    sudo ${EDITOR:-nano} "$base_dir/$container_name/compose.yaml"
    # Create .env file
    sudo sh -c "echo -e \"PUID=1000\nPGID=1000\nTZ=\"Europe/Amsterdam\"\nDOCKERDIR=\"$base_dir\"\nDATADIR=\"$base_dir/$container_name/appdata\"\" > '$base_dir/$container_name/.env'"
    sudo ${EDITOR:-nano} "$base_dir/$container_name/.env"
    # Ask to create new folders in appdata
    read -p "Do you want to create any new folders in the appdata directory? (y/n): " create_folders
    if [[ "$create_folders" =~ ^[Yy]$ ]]; then
        create_appdata_folders "$container_name"
    fi
    reapply_permissions "$container_name"
    echo "Container $container_name created successfully."
    # Ask to run the container
    read -p "Do you want to compose the container now? (y/n): " compose_container
    if [[ "$compose_container" =~ ^[Yy]$ ]]; then
        compose_container "$container_name"
    fi
}

# Apply user permissions
reapply_permissions() {
    local container_name=$1
    # Set directory permissions
    sudo chmod 700 "$base_dir/$container_name"
    sudo chmod 700 "$base_dir/$container_name/appdata"
    sudo chmod 700 "$base_dir/$container_name/logs"
    sudo chmod 400 "$base_dir/$container_name/secrets"
    sudo chmod 400 "$base_dir/$container_name/compose.yaml"
    sudo chmod 400 "$base_dir/$container_name/.env"
    # Change ownership to podman user
    sudo chown -R podman:podman "$base_dir/$container_name"
    # Load rootless_user if it exists
    if [ -f "$base_dir/$container_name/.env" ]; then
        load_rootless_user "$container_name"
        if [ -n "$rootless_user" ]; then
            # Use podman unshare to change ownership inside the container's user namespace
            podman unshare chown -R "$rootless_user:$rootless_user" "$base_dir/$container_name/appdata/"
        fi
    fi
    echo "Permissions applied successfully."
}

# Load rootless_user from .env
load_rootless_user() {
    local container_name=$1
    local env_file="$base_dir/$container_name/.env"
    if [[ ! -r "$env_file" ]]; then
        echo "Cannot read $env_file" >&2
        return 1
    fi
    # Get the line rootless_user=...
    local line
    line=$(sudo grep -m1 -E '^[[:space:]]*rootless_user[[:space:]]*=' "$env_file") || {
        echo "rootless_user not found in $env_file" >&2
        return 1
    }
    # Extract value, strip inline comments/whitespace and surrounding quotes
    local val=${line#*=}
    val=${val%%#*}
    val=$(printf '%s\n' "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    val=$(printf '%s\n' "$val" | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/")
    if [[ -z "$val" ]]; then
        echo "rootless_user value is empty in $env_file" >&2
        return 1
    fi
    rootless_user="$val"
    export rootless_user
}

# Function to update rootless_user in .env
update_rootless_user() {
    local container_name=$1
    local env_file="$base_dir/$container_name/.env"
    # Get HUSER for user "abc"
    local podman_huser
    podman_huser=$(podman top "$container_name" user huser 2>/dev/null | awk 'NR>1 && $1=="abc" {print $2; exit}')
    if [ -z "$podman_huser" ]; then
        echo "Could not determine HUSER for user 'abc' in container '$container_name'. Is it running and does user exist?"
        return 1
    fi
    if [ -e "$env_file" ]; then
        # Check if file is writable, if not make it writable temporarily
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
        # Restore original permissions if we changed them
        if [ ! -w "$env_file" ]; then
            sudo chmod u-w "$env_file"
        fi
    else
        # Create new file with the key
        sudo sh -c "printf 'rootless_user=%s\n' '$podman_huser' > '$env_file'"
    fi
    echo "Updated rootless_user in .env"
}

# Function to remove a container
remove_container() {
    local container_name=$1
    # Stop the container first
    stop_container "$container_name"
    # Remove the container
    podman rm "$container_name"
    # Decompose the container
    decompose_container "$container_name"
    # Ask to remove ALL container data
    if confirm_action "Do you want to remove ALL container data from $container_name?"; then
        if confirm_action "!! Are you sure you want to remove ALL container data from $container_name? !!"); then
            sudo rm -rf "$base_dir/$container_name"
            echo "ALL container data removed from $container_name."
        fi
    fi
    echo "Container $container_name removed successfully."
}

# Function to edit files using ranger
edit_files() {
    # Check if ranger is installed
    if ! command -v ranger &> /dev/null; then
        echo "Ranger is not installed. Please install it first."
        if confirm_action "Do you want to install ranger now?"; then
            sudo apt-get update
            sudo apt-get upgrade -y
            sudo apt-get install -y ranger
        else
            echo "Cannot proceed without ranger. Exiting..."
            return 1
        fi
    fi

    # Get container name
    local container_name=$(prompt_user "Enter the container name to edit files:")

    # Check if container exists
    if ! podman inspect "$container_name" &> /dev/null; then
        echo "Error: Container $container_name does not exist."
        return 1
    fi

    # Check if container is running
    local status=$(podman inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null)
    if [ "$status" != "running" ]; then
        echo "Error: Container $container_name is not running. Please start it first."
        return 1
    fi

    # Explain how to use ranger
    echo "You are now entering the ranger file manager."
    echo "To navigate:"
    echo "- Use the arrow keys to move the cursor."
    echo "- Press Enter to open a file or directory."
    echo "- Press 'q' to quit ranger."
    echo "- To create a new file, press 'o' and enter the file name."
    echo "- To create a new directory, press 'd' and enter the directory name."
    echo "- To delete a file or directory, select it and press 'dd'."
    echo "- To edit a file, select it and press 'e'."
    echo "- To save changes and exit, press 'q' and confirm when prompted."

    # Open ranger in the container's appdata directory
    ranger "$base_dir/$container_name/appdata"
}

# Main menu
while true; do
    echo "Podman Container Management Menu"
    echo "1. List all containers"
    echo "2. Start a container"
    echo "3. Stop a container"
    echo "4. Create a new container"
    echo "5. Compose a container"
    echo "6. Decompose a container"
    echo "7. Edit files using ranger"
    echo "99. Remove a container"
    echo "0. Exit"
    read -p "Enter your choice (0-7, 99): " choice
    case $choice in
        1)
            list_containers
            ;;
        2)
            read -p "Enter the container name to start: " container_name
            start_container "$container_name"
            ;;
        3)
            read -p "Enter the container name to stop: " container_name
            stop_container "$container_name"
            ;;
        4)
            read -p "Enter the new container name: " container_name
            create_container "$container_name"
            ;;
        5)
            read -p "Enter the container name to compose: " container_name
            compose_container "$container_name"
            ;;
        6)
            read -p "Enter the container name to decompose: " container_name
            decompose_container "$container_name"
            ;;
        7)
            edit_files
            ;;
        99)
            read -p "Enter the container name to remove: " container_name
            remove_container "$container_name"
            ;;
        0)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid choice. Please enter a valid option."
            ;;
    esac
    # Wait for user to press Enter before continuing
    read -p "Press Enter to continue..."
done
