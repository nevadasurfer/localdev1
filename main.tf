# main.tf
terraform {
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.8.0"
    }
  }

  required_version = ">= 1.3.0"
}

# Provider for kind
provider "kind" {}

# Define the kind cluster with 2 worker nodes
resource "kind_cluster" "k8s" {
  name = "my-cluster"

}

# Provider for helm, connected to the kind cluster
provider "helm" {
  kubernetes {
    config_path = kind_cluster.k8s.kubeconfig
  }
}




