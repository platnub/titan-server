#!/bin/bash

# Function to create a new container
create_container() {
    read -p "Enter the container name: " container_name
    mkdir -p "/home/podman/containers/$container_name"
    chmod -R 755 "/home/podman/containers/$container_name"

    # Create compose.yaml file
    nano "/home/podman/containers/$container_name/compose.yaml"

    # Ask if user wants to create a .env file
    read -p "Do you want to create a .env file? (y/n): " create_env
    if [ "$create_env" = "y" ]; then
        nano "/home/podman/containers/$container_name/.env"
    fi

    echo "Container $container_name created successfully."
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
