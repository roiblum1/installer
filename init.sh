#!/bin/bash
# initialize-disconnected.sh - Setup script for disconnected OpenShift installation

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISCONNECTED_DIR="${SCRIPT_DIR}/disconnected"
RHCOS_OVA_PATH="${RHCOS_OVA_PATH:-${DISCONNECTED_DIR}/rhcos.ova}"
TERRAFORM_PLUGIN_CACHE="${HOME}/.terraform.d/plugin-cache"

# Define required OpenShift installer version
REQUIRED_OPENSHIFT_VERSION="${REQUIRED_OPENSHIFT_VERSION:-4.14.8}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Create necessary directories
mkdir -p "${DISCONNECTED_DIR}"
mkdir -p "${TERRAFORM_PLUGIN_CACHE}"

# Print a status message
print_status() {
  echo -e "${GREEN}==>${NC} $1"
}

# Print a warning message
print_warning() {
  echo -e "${YELLOW}==>${NC} $1"
}

# Print an error message and exit
print_error() {
  echo -e "${RED}ERROR:${NC} $1"
  exit 1
}

# Check if required tools are available
check_command() {
  if ! command -v "$1" &> /dev/null; then
    print_error "$1 is required but not installed. Please install it first."
  fi
}

# Required commands
check_command terraform
check_command nsupdate
check_command openshift-install

# Check if install-config.yaml exists
if [ ! -f "${SCRIPT_DIR}/install-config.yaml" ]; then
  print_error "install-config.yaml not found in ${SCRIPT_DIR}. This file is required."
fi

# Check OpenShift installer version
INSTALLED_OPENSHIFT_VERSION=$(openshift-install version | head -n1 | awk '{print $2}' | sed 's/^v//')
if [ "$INSTALLED_OPENSHIFT_VERSION" != "$REQUIRED_OPENSHIFT_VERSION" ]; then
  print_error "OpenShift installer version $INSTALLED_OPENSHIFT_VERSION does not match the required version $REQUIRED_OPENSHIFT_VERSION."
fi
print_status "OpenShift installer version $INSTALLED_OPENSHIFT_VERSION verified."

print_status "Starting disconnected OpenShift installation setup"

# Check for RHCOS OVA template 
if [ ! -f "${RHCOS_OVA_PATH}" ]; then
  print_warning "RHCOS OVA not found at ${RHCOS_OVA_PATH}"
  print_warning "For a disconnected environment, you need to pre-download the OVA file."
  print_warning "If you've already uploaded the OVA template to vSphere, you can ignore this warning."
  print_warning "Set RHCOS_OVA_PATH environment variable to specify a different location."
fi

# Create ignition configs if they don't exist
if [ ! -d "${SCRIPT_DIR}/auth" ] || [ ! -f "${SCRIPT_DIR}/bootstrap.ign" ]; then
  print_status "Creating ignition configs from install-config.yaml"
  
  # Backup install-config.yaml
  cp "${SCRIPT_DIR}/install-config.yaml" "${DISCONNECTED_DIR}/install-config.yaml.bak"
  
  # Create manifests
  print_status "Creating manifests..."
  openshift-install create manifests --dir="${SCRIPT_DIR}"
  
  # Remove machine configs for UPI installation
  print_status "Removing machine configs for UPI installation..."
  rm -f ${SCRIPT_DIR}/openshift/99_openshift-cluster-api_master-machines-*.yaml
  rm -f ${SCRIPT_DIR}/openshift/99_openshift-cluster-api_worker-machineset-*.yaml
  
  # Create ignition configs
  print_status "Creating ignition configs..."
  openshift-install create ignition-configs --dir="${SCRIPT_DIR}"
  
  # Restore install-config.yaml
  cp "${DISCONNECTED_DIR}/install-config.yaml.bak" "${SCRIPT_DIR}/install-config.yaml"
  
  print_status "Ignition configs created successfully"
else
  print_status "Ignition configs already exist, skipping creation"
fi

# Configure Terraform for disconnected environment
export TF_PLUGIN_CACHE_DIR="${TERRAFORM_PLUGIN_CACHE}"

# Initialize Terraform (assuming plugins are cached or locally available)
print_status "Initializing Terraform"
terraform init

# Validate the Terraform configuration
print_status "Validating Terraform configuration"
terraform validate

if [ $? -eq 0 ]; then
  print_status "Environment preparation complete"
  print_status "You can now run 'terraform apply' to start the installation"
  echo ""
  echo "Next steps:"
  echo "1. Review/edit terraform.tfvars to match your environment"
  echo "2. Run 'terraform apply' to create the infrastructure"
  echo "3. Monitor the installation with 'openshift-install wait-for bootstrap-complete'"
  echo "4. Once bootstrap is complete, run 'terraform apply -var bootstrap_complete=true'"
  echo "5. Monitor installation completion with 'openshift-install wait-for install-complete'"
else
  print_error "Terraform validation failed. Please fix the errors before continuing."
fi