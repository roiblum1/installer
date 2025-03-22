#!/bin/bash
# scan_cidr_for_free_ip.sh
# This script accepts JSON input containing a CIDR block and an optional "hosts" field.
# For example: {"cidr": "10.0.0.0/24", "hosts": 3}
# It scans all IP addresses in that CIDR range, performing a ping and nslookup on each.
# It collects free IP addresses (those that do not respond to ping and have no reverse DNS record)
# until it has found the requested number of free IPs.
#
# Usage example:
#   echo '{"cidr": "10.0.0.0/24", "hosts": 3}' | ./scan_cidr_for_free_ip.sh
function error_exit() {
  echo "$1" >&2
  exit 1
}

# Check for required dependencies: jq, ping, nslookup
function check_deps() {
  command -v jq >/dev/null 2>&1 || error_exit "jq command not detected in path, please install it"
  command -v ping >/dev/null 2>&1 || error_exit "ping command not detected in path"
  command -v nslookup >/dev/null 2>&1 || error_exit "nslookup command not detected in path"
}

# Convert an IP address (dotted notation) to a 32-bit integer
ip2int() {
  local a b c d
  IFS=. read -r a b c d <<< "$1"
  echo $((a * 256**3 + b * 256**2 + c * 256 + d))
}

# Convert a 32-bit integer to an IP address (dotted notation)
int2ip() {
  local ui32=$1
  local ip n
  for n in 3 2 1 0; do
    ip_part=$(( (ui32 >> (n * 8)) & 0xFF ))
    printf "%d" "$ip_part"
    if [ $n -gt 0 ]; then
      printf "."
    fi
  done
}

# Parse JSON input from STDIN and extract the CIDR block and hosts count.
function parse_input() {
  input=$(jq .) || error_exit "Invalid JSON input"
  cidr=$(echo "$input" | jq -r .cidr)
  if [[ "$cidr" == "null" || -z "$cidr" ]]; then
    error_exit "JSON input must include a 'cidr' field (e.g., \"cidr\": \"10.0.0.0/24\")"
  fi
  # Retrieve the number of required hosts; default to 1 if not provided.
  hosts=$(echo "$input" | jq -r .hosts)
  if [[ "$hosts" == "null" || -z "$hosts" ]]; then
    hosts=1
  fi
  # Validate that hosts is a positive integer.
  if ! [[ "$hosts" =~ ^[1-9][0-9]*$ ]]; then
    error_exit "The 'hosts' field must be a positive integer"
  fi
}

# Calculate the network and broadcast addresses for a given CIDR.
# Sets two global variables: network_int and broadcast_int.
function calc_range() {
  local base mask
  base=$(echo "$cidr" | cut -d'/' -f1)
  mask=$(echo "$cidr" | cut -d'/' -f2)
  if ! [[ "$mask" =~ ^[0-9]+$ && $mask -ge 0 && $mask -le 32 ]]; then
    error_exit "Invalid CIDR mask in $cidr"
  fi

  local base_int
  base_int=$(ip2int "$base")
  # Calculate the network address (zero out the host bits)
  network_int=$(( base_int & ~((1 << (32 - mask)) - 1) ))
  
  # Calculate the broadcast address (set all host bits to 1)
  broadcast_int=$(( network_int + (1 << (32 - mask)) - 1 ))
}

# Check if an IP is active by pinging it.
function is_pingable() {
  local ip=$1
  # Send one ICMP packet with a 1-second timeout.
  if ping -c 1 -W 1 "$ip" >/dev/null 2>&1; then
    echo "yes"
  else
    echo "no"
  fi
}

# Check if an IP has a reverse DNS (PTR) record using nslookup.
function has_dns_record() {
  local ip=$1
  ns_out=$(nslookup "$ip" 2>&1)
  # Many nslookup outputs include "name =" if a PTR record is found.
  if echo "$ns_out" | grep -qi "name ="; then
    echo "yes"
  else
    echo "no"
  fi
}

# Loop through the usable IPs in the CIDR range to find free IPs until we have the required number.
function scan_cidr() {
  local candidate
  local -a free_ips=()
  # Typically, the network and broadcast addresses are not usable.
  # Also, skip the first usable IP (typically used as gateway) by starting at network_int+2.
  for (( i = network_int + 2; i < broadcast_int; i++ )); do
    candidate=$(int2ip $i)
    # Check if the candidate IP responds to ping.
    if [ "$(is_pingable "$candidate")" == "yes" ]; then
      echo "IP $candidate is active (ping responded), skipping..." >&2
      continue
    fi
    # Check if the candidate IP has a reverse DNS record.
    if [ "$(has_dns_record "$candidate")" == "yes" ]; then
      echo "IP $candidate has a DNS record, skipping..." >&2
      continue
    fi
    # Candidate is free, add it to the free_ips array.
    free_ips+=("$candidate")
    # If we have found the required number of free IPs, break out of the loop.
    if [ "${#free_ips[@]}" -ge "$hosts" ]; then
      break
    fi
  done

  if [ "${#free_ips[@]}" -lt "$hosts" ]; then
    error_exit "Only found ${#free_ips[@]} free IPs in CIDR $cidr, required $hosts"
  else
    # Output the free IPs as a JSON array with key "ip_addresses".
    json_array=$(printf '%s\n' "${free_ips[@]}" | jq -R . | jq -s .)
    jq -n --arg ip_addresses "$json_array" '{"ip_addresses": $ip_addresses}'
  fi
}

# Main execution flow.
check_deps
parse_input
calc_range
scan_cidr
