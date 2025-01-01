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

resource "kind_cluster" "k8s" {
  name           = "localdev1"
  node_image     = "kindest/node:v1.32.0"
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"
      extra_port_mappings {
        container_port = 80
        host_port      = 80
      }
    }

    node {
      role = "worker1"
    }
    node {
      role = "worker2"
    }
  }
}

# Provider for helm, connected to the kind cluster
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}




