#!/bin/bash -e

if [ "$1" = "--force" ]; then
    echo "Force flag detected. Proceeding without confirmation."
    exit 0
fi

echo "Are you sure you want to proceed? (y/N)"
read -r answer

if [[ "$answer" != "y" ]]; then
    echo "Aborting."
    exit 1
fi
