#!/usr/bin/pwsh
# Post-installation script to configure infrastructure nodes
# Run this after the OpenShift cluster is fully operational

# Load configuration values
. ./variables.ps1

# Configure infrastructure nodes
Write-Output "Configuring infrastructure nodes..."

# First verify connection to the cluster
$kubeconfig = "./auth/kubeconfig"
if (-not (Test-Path $kubeconfig)) {
    Write-Error "Kubeconfig not found at $kubeconfig. Please make sure the cluster is installed."
    exit 1
}

# Set KUBECONFIG environment variable to our cluster config
$env:KUBECONFIG = Resolve-Path $kubeconfig

# Verify connection before proceeding
try {
    $ocOutput = & oc get nodes
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Unable to connect to the cluster using oc. Please check your configuration."
        exit 1
    }
} catch {
    Write-Error "Error executing oc command: $_"
    exit 1
}

# Check for infrastructure nodes - the script assumes they're named with the pattern infraID-infra-#
$infraNodes = & oc get nodes -l node-role.kubernetes.io/worker -o name | Where-Object { $_ -match "infra-[0-9]+" }
if ($infraNodes.Count -eq 0) {
    Write-Output "No infrastructure nodes found. Checking for regular worker nodes with 'infra' in their name..."
    $infraNodes = & oc get nodes -o name | Where-Object { $_ -match "infra-[0-9]+" }
    
    if ($infraNodes.Count -eq 0) {
        Write-Error "No infrastructure nodes found in the cluster. Please make sure infrastructure nodes were created correctly."
        exit 1
    }
}

# 1. Apply infrastructure node role label
Write-Output "Adding infrastructure node role labels..."
foreach ($node in $infraNodes) {
    $nodeName = $node -replace "node/", ""
    & oc label node/$nodeName node-role.kubernetes.io/infra="" --overwrite
    # Remove worker role if it exists
    & oc label node/$nodeName node-role.kubernetes.io/worker- --overwrite
}

# 2. Add RHCOS labels if needed
Write-Output "Adding RHCOS labels to infrastructure nodes..."
foreach ($node in $infraNodes) {
    $nodeName = $node -replace "node/", ""
    & oc label node/$nodeName node.openshift.io/os_id=rhcos --overwrite
}

# 3. Add scheduler taint to prevent normal workloads
Write-Output "Adding taints to infrastructure nodes..."
foreach ($node in $infraNodes) {
    $nodeName = $node -replace "node/", ""
    & oc adm taint node/$nodeName node-role.kubernetes.io/infra:NoSchedule --overwrite
}

# 4. Move router to infrastructure nodes
Write-Output "Moving Ingress router to infrastructure nodes..."
$ingressYaml = @"
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: default
  namespace: openshift-ingress-operator
spec:
  nodePlacement:
    nodeSelector:
      matchLabels:
        node-role.kubernetes.io/infra: ""
    tolerations:
    - effect: NoSchedule
      key: node-role.kubernetes.io/infra
      operator: Exists
"@

$ingressYaml | Set-Content -Path ./ingress-config.yaml
& oc apply -f ./ingress-config.yaml

# 5. Move registry to infrastructure nodes (if registry is configured)
Write-Output "Moving image registry to infrastructure nodes..."
$registryConfig = & oc get configs.imageregistry.operator.openshift.io/cluster -o json | ConvertFrom-Json

if ($registryConfig) {
    & oc patch configs.imageregistry.operator.openshift.io/cluster --type=merge -p '{"spec":{"nodeSelector":{"node-role.kubernetes.io/infra":""},"tolerations":[{"effect":"NoSchedule","key":"node-role.kubernetes.io/infra","operator":"Exists"}]}}'
    Write-Output "Registry configuration updated"
} else {
    Write-Output "Registry operator config not found - this might be expected in some configurations"
}

# 6. Move monitoring to infrastructure nodes
Write-Output "Moving monitoring components to infrastructure nodes..."
$monitoringYaml = @"
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    prometheusOperator:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: node-role.kubernetes.io/infra
        effect: NoSchedule
        operator: Exists
    prometheusK8s:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: node-role.kubernetes.io/infra
        effect: NoSchedule
        operator: Exists
    alertmanagerMain:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: node-role.kubernetes.io/infra
        effect: NoSchedule
        operator: Exists
    kubeStateMetrics:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: node-role.kubernetes.io/infra
        effect: NoSchedule
        operator: Exists
    grafana:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: node-role.kubernetes.io/infra
        effect: NoSchedule
        operator: Exists
    telemeterClient:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: node-role.kubernetes.io/infra
        effect: NoSchedule
        operator: Exists
    k8sPrometheusAdapter:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: node-role.kubernetes.io/infra
        effect: NoSchedule
        operator: Exists
    openshiftStateMetrics:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: node-role.kubernetes.io/infra
        effect: NoSchedule
        operator: Exists
    thanosQuerier:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: node-role.kubernetes.io/infra
        effect: NoSchedule
        operator: Exists
"@

$monitoringYaml | Set-Content -Path ./monitoring-config.yaml

# Create the namespace if it doesn't exist (it should already exist, but just in case)
& oc get namespace openshift-monitoring > $null 2>&1
if ($LASTEXITCODE -ne 0) {
    & oc create namespace openshift-monitoring
}

& oc apply -f ./monitoring-config.yaml

# Verify configuration
Write-Output "`nVerifying infrastructure node configuration..."
& oc get nodes -l node-role.kubernetes.io/infra=

Write-Output "`nInfrastructure node configuration complete!"
Write-Output "Components will now begin to migrate to infrastructure nodes. This process may take several minutes."

# Check if DNS records need updating
if ($ingressvip) {
    Write-Output "`nUpdating wildcard DNS record for *.apps to point to infrastructure nodes..."
    # This would normally update the wildcard DNS entry to point to the infrastructure nodes load balanced VIP
    # Uncomment and modify this if you're using a load balancer in front of infra nodes
    # & nsupdate -v -d << EOF
    # update delete *.apps.$clustername.$basedomain A
    # update add *.apps.$clustername.$basedomain 8600 A $ingressvip
    # send
    # EOF
}

Write-Output "Post-installation configuration complete!"