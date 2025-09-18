# AWS-EKS-TERRAFORM-HELM-ARGOCD

### 1. Install Terraform

These steps will add the official HashiCorp repository and install the Terraform CLI.

```bash
# First, update package lists and install necessary dependencies
sudo apt-get update && sudo apt-get install -y gpg software-properties-common

# Add the HashiCorp GPG key
wget -O- [https://apt.releases.hashicorp.com/gpg](https://apt.releases.hashicorp.com/gpg) | \
gpg --dearmor | \
sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null

# Add the official HashiCorp repository
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] [https://apt.releases.hashicorp.com](https://apt.releases.hashicorp.com) $(lsb_release -cs) main" | \
sudo tee /etc/apt/sources.list.d/hashicorp.list

# Update and install Terraform
sudo apt-get update && sudo apt-get install terraform -y

# Verify the installation
terraform --version


### 2.Install the 'unzip' utility if not already present
sudo apt-get install -y unzip

# Download the AWS CLI installer
curl "[https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip](https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip)" -o "awscliv2.zip"

# Unzip the installer and run the installation script
unzip awscliv2.zip
sudo ./aws/install

# Clean up the downloaded files
rm awscliv2.zip
rm -rf ./aws

# Verify the installation
aws --version


### 3.Download the installer script
curl -fsSL -o get_helm.sh [https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3](https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3)

# Make the script executable and run it
chmod 700 get_helm.sh
./get_helm.sh

# Clean up the script
rm get_helm.sh

# Verify the installation
helm version


## --------------------------------------------------------------------------


### 2 MAJOR ISSUES FACED:

## 1. Initial `terraform apply` and Authentication

### The Symptom
On the very first `terraform apply` for a new environment, the command may successfully create the EKS cluster but then fail with an **`Unauthorized`** error when attempting to create Kubernetes resources like the Helm releases or the Ingress.

### The Cause
This is a timing and authentication initialization issue. The Terraform Kubernetes and Helm providers attempt to authenticate with the new EKS cluster's API server immediately after its creation. However, the cluster may not be fully ready to authenticate the IAM user (the cluster creator) via the token that Terraform generates on this first run.

Running the `aws eks update-kubeconfig` command manually configures your local `kubectl` and validates your administrative access to the cluster. This action effectively "primes" the authentication path.

### The Manual Workaround
To resolve this, a two-step apply is required for the initial creation.

1.  **Run `terraform apply` for the first time.** The apply will proceed, create the EKS cluster, and then fail on the Kubernetes resources. This is expected.

2.  **Run the `update-kubeconfig` command.** After the first `apply` fails, run the command that was generated in your Terraform output to configure `kubectl`.
    ```bash
    aws eks update-kubeconfig --region us-east-1 --name staging-eks-demo
    ```

3.  **Run `terraform apply` again.** With your identity now fully authenticated against the cluster, run the apply command a second time. Terraform will see that the cluster already exists and will now have the authorization to successfully create all the remaining Kubernetes and Helm resources.



## 2.Manual Cleanup for Stuck Ingress Resources

This procedure is necessary when a `terraform destroy` command gets stuck while trying to delete a Kubernetes `Ingress` resource. This typically happens if the AWS Load Balancer Controller pods are not running, leaving the `Ingress` "locked" by a **finalizer**.

The controller's broken validating webhook can also block any manual attempts to fix the Ingress. The solution is a two-step manual override.

### Step 1: Delete the Blocking Webhook

First, we must delete the `ValidatingWebhookConfiguration`. This removes the block that prevents us from modifying the stuck Ingress resource.

```bash
# Delete the validating webhook installed by the ALB Controller
kubectl delete validatingwebhookconfigurations aws-load-balancer-webhook
