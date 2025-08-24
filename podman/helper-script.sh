#!/bin/bash
base_dir="/home/podman/containers"

# Function to create a new container
create_container() {
    read -p "Enter the container name: " container_name
    read -p "Enter the user ID (UID) to use: " user_id

    # Create a non-login system user with the given UID
    # -r system user, -U create group, -M no home, -s nologin shell
    if ! id -u "$container_name" >/dev/null 2>&1; then
      useradd -r -U -u "$user_id" -M -s /usr/sbin/nologin -d "$base_dir/$container_name" "$container_name"
    else
      echo "User $container_name already exists; skipping creation."
    fi

    # Lock password to prevent password-based login
    passwd -l "$container_name"

    # Create container directories
    mkdir -p "$base_dir/$container_name"
    mkdir -p "$base_dir/$container_name/appdata"
    mkdir -p "$base_dir/$container_name/logs"
    mkdir -p "$base_dir/$container_name/secrets"
    
    # Create compose.yaml
    ${EDITOR:-nano} "$base_dir/$container_name/compose.yaml"
    
    # Optional .env
    echo -e "PUID=$user_id\nPGID=$user_id\nTZ=\"Europe/Amsterdam\"\nDOCKERDIR=\"$base_dir\"\nDATADIR=\"$base_dir/$container_name/appdata\"" > "$base_dir/$container_name/.env"
    ${EDITOR:-nano} "$base_dir/$container_name/.env"

    # Apply user permissions
    chmod 600 "$base_dir/$container_name"
    chown -R "$container_name" "$base_dir/$container_name"
    

    echo "Container $container_name created successfully with user."
}

# Function to list all containers
list_containers() {
    echo "Listing all Podman containers:"
    podman ps -a
}

# Function to remove a container
remove_container() {
    read -p "Enter the container name to remove: " container_name
    podman stop "$container_name"
    podman rm "$container_name"
    rm -rf "/home/podman/containers/$container_name"
    echo "Container $container_name removed successfully."
}

# Main menu
while true; do
    echo "Podman Container Management Menu"
    echo "1. Create a new container"
    echo "2. List all containers"
    echo "3. Remove a container"
    echo "4. Exit"
    read -p "Enter your choice (1-4): " choice

    case $choice in
        1)
            create_container
            ;;
        2)
            list_containers
            ;;
        3)
            remove_container
            ;;
        4)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid choice. Please enter a number between 1 and 4."
            ;;
    esac
done
