#!/bin/bash
base_dir="/home/podman/containers"

# Function to list all containers
list_containers() {
    echo "Listing all Podman containers:"
    podman ps -a
}

# Function to run a container
run_container() {
    local container_name=$1
    reapply_permissions "$container_name"
    podman-compose --file "$base_dir/$container_name/compose.yaml" up --detach
    update_rootless_user "$container_name"
    echo "Container $container_name started successfully."
}

# Function to stop a container
stop_container() {
    local container_name=$1
    update_rootless_user "$container_name"
    podman-compose --file "$base_dir/$container_name/compose.yaml" down
    echo "Container $container_name stopped successfully."
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

    reapply_permissions "$container_name"
    echo "Container $container_name created successfully."

    # Ask to run the container
    read -p "Do you want to run the container now? (y/n): " create_run_container
    if [[ "$create_run_container" =~ ^[Yy]$ ]]; then
        run_container "$container_name"
    fi
}

# Apply user permissions
reapply_permissions() {
    local container_name=$1

    sudo chmod 700 "$base_dir/$container_name"
    sudo chmod 700 "$base_dir/$container_name/appdata"
    sudo chmod 700 "$base_dir/$container_name/logs"
    sudo chmod 400 "$base_dir/$container_name/secrets"
    sudo chmod 400 "$base_dir/$container_name/compose.yaml"
    sudo chmod 400 "$base_dir/$container_name/.env"

    ( cd "$base_dir/$container_name" && sudo chown podman:podman * )
    
    # Load rootless_user if it exists
    if [ -f "$base_dir/$container_name/.env" ]; then
        load_rootless_user "$container_name"
        if [ -n "$rootless_user" ]; then
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

    # Ask to remove ALL container data
    read -p "Do you want to remove ALL container data from $container_name? (y/n): " remove_container_data
    if [[ "$remove_container_data" =~ ^[Yy]$ ]]; then
        read -p "!! Are you sure you want to remove ALL container data from $container_name? !! (y/n): " remove_container_data_sure
        if [[ "$remove_container_data_sure" =~ ^[Yy]$ ]]; then
            sudo rm -rf "$base_dir/$container_name"
            echo "ALL container data removed from $container_name."
        fi
    fi

    echo "Container $container_name removed successfully."
}

# Main menu
while true; do
    echo "Podman Container Management Menu"
    echo "1. List all containers"
    echo "2. Run a container"
    echo "3. Stop a container"
    echo "4. Create a new container"
    echo "99. Remove a container"
    echo "5. Exit"
    read -p "Enter your choice (1-5): " choice

    case $choice in
        1)
            list_containers
            ;;
        2)
            read -p "Enter the container name to run: " container_name
            run_container "$container_name"
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
            echo "Exiting..."
            exit 0
            ;;
        99)
            read -p "Enter the container name to remove: " container_name
            remove_container "$container_name"
            ;;
        *)
            echo "Invalid choice. Please enter a number between 1 and 6."
            ;;
    esac
done
