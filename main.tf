terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "2.9.0"
    }
  }
}

#provider "helm" {
#  kubernetes {
#    config_path = "~/.kube/config" # Path to your Kubernetes config file
#  }
#}

provider "kind" {}
locals {
  k8s_config_path = pathexpand("~/.kube/config")
}

# creating a cluster with kind of the name "test-cluster" with kubernetes version v1.27.1 and two nodes
resource "kind_cluster" "default" {
  name            = "test-cluster"
  kubeconfig_path = local.k8s_config_path
  node_image      = "kindest/node:v1.31.2"
  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"
    node {
      role = "control-plane"
    }
    node {
      role = "worker1"
    }
    node {
      role = "worker2"
    }
  }
}


