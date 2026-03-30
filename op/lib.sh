#!/bin/bash

# Common library for wait scripts

# Get the top directory (based on lib.sh location, not caller)
get_top_dir() {
  cd "$( dirname "${BASH_SOURCE[0]}" )/.." &> /dev/null && pwd
}

# Get the config file path
get_config_file() {
  echo "$(get_top_dir)/config.yaml"
}

# Get the harvester-smoke directory path
get_smoke_tests_dir() {
  echo "$(get_top_dir)/harvester-smoke"
}

# Get IP from terraform output
# Usage: get_tf_output <tf_dir> <output_name>
get_tf_output() {
  local tf_dir="$1"
  local output_name="$2"
  terraform -chdir="$tf_dir" output -json | jq -r ".${output_name}.value"
}

# Get and validate IP from terraform output
# Usage: get_vm_ip <tf_dir> <output_name> <vm_name>
get_vm_ip() {
  local tf_dir="$1"
  local output_name="$2"
  local vm_name="$3"
  
  local ip=$(get_tf_output "$tf_dir" "$output_name")
  
  if [ -z "$ip" ] || [ "$ip" = "null" ]; then
    echo "Error: Could not retrieve $vm_name IP address from Terraform output" >&2
    exit 1
  fi
  
  echo "$ip"
}

# Wait for SSH connection
# Usage: wait_for_ssh <hostname> <timeout_minutes>
wait_for_ssh() {
  local hostname="$1"
  local timeout_minutes="${2:-1}"
  
  local top_dir=$(get_top_dir)
  local ssh_config="$top_dir/state/ssh_config"
  
  echo "Waiting for $hostname to be up and accepting SSH connections..."
  
  if [ ! -f "$ssh_config" ]; then
    echo "Error: SSH config file not found at $ssh_config" >&2
    echo "Please run 'terraform apply' to generate the SSH config file" >&2
    return 1
  fi
  
  local max_attempts=$((timeout_minutes * 12))
  local count=0
  
  while true; do
    if ssh -F "$ssh_config" "$hostname" "echo SSH connection successful && exit" 2>/dev/null; then
      echo "SSH connection to $hostname successful!"
      return 0
    else
      echo "Not yet up. Retrying in 5 seconds..."
      sleep 5
    fi
    
    count=$((count + 1))
    if [ $count -ge $max_attempts ]; then
      echo "Error: SSH connection to $hostname did not become available after $timeout_minutes minute(s)"
      return 1
    fi
  done
}

# Wait for cloud-init to finish
# Usage: wait_for_cloudinit <hostname> <timeout_minutes>
wait_for_cloudinit() {
  local hostname="$1"
  local timeout_minutes="${2:-1}"
  
  local top_dir=$(get_top_dir)
  local ssh_config="$top_dir/state/ssh_config"
  
  echo "Waiting for cloud-init on $hostname to finish..."
  
  if [ ! -f "$ssh_config" ]; then
    echo "Error: SSH config file not found at $ssh_config" >&2
    echo "Please run 'terraform apply' to generate the SSH config file" >&2
    return 1
  fi
  
  local max_attempts=$((timeout_minutes * 12))
  local count=0
  
  while true; do
    if ssh -F "$ssh_config" "$hostname" "test -f /var/lib/cloud/instance/boot-finished" 2>/dev/null; then
      echo "Cloud-init on $hostname finished!"
      return 0
    else
      echo "Cloud-init not yet finished. Retrying in 5 seconds..."
      sleep 5
    fi
    
    count=$((count + 1))
    if [ $count -ge $max_attempts ]; then
      echo "Error: Cloud-init on $hostname did not finish after $timeout_minutes minute(s)"
      return 1
    fi
  done
}

# Start a libvirt domain if it's not already running
# Usage: libvirt_start_domain <domain_name>
libvirt_start_domain() {
  local domain_name="$1"
  
  if [ -z "$domain_name" ]; then
    echo "Error: domain_name is required" >&2
    return 1
  fi
  
  # Check if domain is already running
  local state=$(virsh domstate "$domain_name" 2>/dev/null || echo "not-found")
  
  if [ "$state" = "running" ]; then
    echo "Domain $domain_name is already running, skipping..."
    return 0
  elif [ "$state" = "not-found" ]; then
    echo "Error: Domain $domain_name not found" >&2
    return 1
  else
    echo "Starting domain $domain_name (current state: $state)..."
    virsh start "$domain_name"
    return $?
  fi
}

# Destroy (forcefully shut down) a libvirt domain if it's running
# Usage: libvirt_destroy_domain <domain_name>
libvirt_destroy_domain() {
  local domain_name="$1"
  
  if [ -z "$domain_name" ]; then
    echo "Error: domain_name is required" >&2
    return 1
  fi
  
  # Check if domain exists and get its state
  local state=$(virsh domstate "$domain_name" 2>/dev/null || echo "not-found")
  
  if [ "$state" = "not-found" ]; then
    echo "Error: Domain $domain_name not found" >&2
    return 1
  elif [ "$state" = "shut off" ]; then
    echo "Domain $domain_name is already shut off, skipping..."
    return 0
  else
    echo "Destroying domain $domain_name (current state: $state)..."
    virsh destroy "$domain_name"
    return $?
  fi
}

# Gracefully shutdown a libvirt domain if it's running
# Usage: libvirt_shutdown_domain <domain_name>
libvirt_shutdown_domain() {
  local domain_name="$1"
  
  if [ -z "$domain_name" ]; then
    echo "Error: domain_name is required" >&2
    return 1
  fi
  
  # Check if domain exists and get its state
  local state=$(virsh domstate "$domain_name" 2>/dev/null || echo "not-found")
  
  if [ "$state" = "not-found" ]; then
    echo "Error: Domain $domain_name not found" >&2
    return 1
  elif [ "$state" = "shut off" ]; then
    echo "Domain $domain_name is already shut off, skipping..."
    return 0
  else
    echo "Shutting down domain $domain_name gracefully (current state: $state)..."
    virsh shutdown "$domain_name"
    return $?
  fi
}

# Create a snapshot of a libvirt domain
# Usage: libvirt_snapshot_domain <domain_name> <snapshot_name>
libvirt_snapshot_domain() {
  local domain_name="$1"
  local snapshot_name="$2"
  
  if [ -z "$domain_name" ]; then
    echo "Error: domain_name is required" >&2
    return 1
  fi
  
  if [ -z "$snapshot_name" ]; then
    echo "Error: snapshot_name is required" >&2
    return 1
  fi
  
  # Check if domain exists
  local state=$(virsh domstate "$domain_name" 2>/dev/null || echo "not-found")
  
  if [ "$state" = "not-found" ]; then
    echo "Error: Domain $domain_name not found" >&2
    return 1
  fi
  
  echo "Creating snapshot '$snapshot_name' for domain $domain_name (current state: $state)..."
  virsh snapshot-create-as --domain "$domain_name" --name "$snapshot_name" --description "Snapshot created on $(date)"
  
  if [ $? -eq 0 ]; then
    echo "Snapshot '$snapshot_name' created successfully for $domain_name"
    return 0
  else
    echo "Error: Failed to create snapshot '$snapshot_name' for $domain_name" >&2
    return 1
  fi
}

# Revert a libvirt domain to a snapshot
# Usage: libvirt_revert_snapshot <domain_name> <snapshot_name>
libvirt_revert_snapshot() {
  local domain_name="$1"
  local snapshot_name="$2"
  
  if [ -z "$domain_name" ]; then
    echo "Error: domain_name is required" >&2
    return 1
  fi
  
  if [ -z "$snapshot_name" ]; then
    echo "Error: snapshot_name is required" >&2
    return 1
  fi
  
  # Check if domain exists
  local state=$(virsh domstate "$domain_name" 2>/dev/null || echo "not-found")
  
  if [ "$state" = "not-found" ]; then
    echo "Error: Domain $domain_name not found" >&2
    return 1
  fi
  
  # Check if snapshot exists
  if ! virsh snapshot-list "$domain_name" --name | grep -q "^${snapshot_name}$"; then
    echo "Error: Snapshot '$snapshot_name' not found for domain $domain_name" >&2
    return 1
  fi
  
  echo "Reverting domain $domain_name to snapshot '$snapshot_name' (current state: $state)..."
  virsh snapshot-revert --domain "$domain_name" --snapshotname "$snapshot_name"
  
  if [ $? -eq 0 ]; then
    echo "Domain $domain_name successfully reverted to snapshot '$snapshot_name'"
    return 0
  else
    echo "Error: Failed to revert $domain_name to snapshot '$snapshot_name'" >&2
    return 1
  fi
}

# List all snapshots for a libvirt domain
# Usage: libvirt_list_snapshots <domain_name>
libvirt_list_snapshots() {
  local domain_name="$1"
  
  if [ -z "$domain_name" ]; then
    echo "Error: domain_name is required" >&2
    return 1
  fi
  
  # Check if domain exists
  local state=$(virsh domstate "$domain_name" 2>/dev/null || echo "not-found")
  
  if [ "$state" = "not-found" ]; then
    echo "Error: Domain $domain_name not found" >&2
    return 1
  fi
  
  echo "Snapshots for domain $domain_name:"
  virsh snapshot-list "$domain_name"
  return $?
}

# Delete all snapshots for a libvirt domain
# Usage: libvirt_delete_all_snapshots <domain_name>
libvirt_delete_all_snapshots() {
  local domain_name="$1"
  
  if [ -z "$domain_name" ]; then
    echo "Error: domain_name is required" >&2
    return 1
  fi
  
  # Check if domain exists
  local state=$(virsh domstate "$domain_name" 2>/dev/null || echo "not-found")
  
  if [ "$state" = "not-found" ]; then
    echo "Error: Domain $domain_name not found" >&2
    return 1
  fi
  
  # Get list of all snapshot names
  local snapshots=$(virsh snapshot-list "$domain_name" --name 2>/dev/null)
  
  if [ -z "$snapshots" ]; then
    echo "No snapshots found for domain $domain_name"
    return 0
  fi
  
  echo "Deleting all snapshots for domain $domain_name..."
  local count=0
  local failed=0
  
  while IFS= read -r snapshot_name; do
    if [ -n "$snapshot_name" ]; then
      echo "  Deleting snapshot: $snapshot_name"
      if virsh snapshot-delete --domain "$domain_name" --snapshotname "$snapshot_name" 2>/dev/null; then
        count=$((count + 1))
      else
        echo "  Error: Failed to delete snapshot '$snapshot_name'" >&2
        failed=$((failed + 1))
      fi
    fi
  done <<< "$snapshots"
  
  if [ $failed -eq 0 ]; then
    echo "Successfully deleted $count snapshot(s) for $domain_name"
    return 0
  else
    echo "Deleted $count snapshot(s), but $failed failed for $domain_name" >&2
    return 1
  fi
}

# Upload a file to a remote host using scp
# Usage: ssh_upload <hostname> <local_path> <remote_path>
ssh_upload() {
  local hostname="$1"
  local local_path="$2"
  local remote_path="$3"
  
  if [ -z "$hostname" ] || [ -z "$local_path" ] || [ -z "$remote_path" ]; then
    echo "Error: hostname, local_path, and remote_path are required" >&2
    echo "Usage: ssh_upload <hostname> <local_path> <remote_path>" >&2
    return 1
  fi
  
  local top_dir=$(get_top_dir)
  local ssh_config="$top_dir/state/ssh_config"
  
  if [ ! -f "$ssh_config" ]; then
    echo "Error: SSH config file not found at $ssh_config" >&2
    echo "Please run 'terraform apply' to generate the SSH config file" >&2
    return 1
  fi
  
  if [ ! -f "$local_path" ] && [ ! -d "$local_path" ]; then
    echo "Error: Local path does not exist: $local_path" >&2
    return 1
  fi
  
  echo "Uploading $local_path to $hostname:$remote_path..."
  scp -F "$ssh_config" "$local_path" "$hostname:$remote_path"
  return $?
}

# Execute a command on a remote host using ssh
# Usage: ssh_exec <hostname> <command>
ssh_exec() {
  local hostname="$1"
  shift  # Remove first argument, leaving the command
  local command="$@"
  
  if [ -z "$hostname" ] || [ -z "$command" ]; then
    echo "Error: hostname and command are required" >&2
    echo "Usage: ssh_exec <hostname> <command>" >&2
    return 1
  fi
  
  local top_dir=$(get_top_dir)
  local ssh_config="$top_dir/state/ssh_config"
  
  if [ ! -f "$ssh_config" ]; then
    echo "Error: SSH config file not found at $ssh_config" >&2
    echo "Please run 'terraform apply' to generate the SSH config file" >&2
    return 1
  fi
  
  echo "Executing on $hostname: $command"
  ssh -F "$ssh_config" "$hostname" "$command"
  return $?
}
