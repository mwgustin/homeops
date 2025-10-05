terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.36.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = ">= 1.0.0"
    }
  }
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "gustend"
    workspaces {
      name = "gustend-main"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "sops" {}

data "sops_file" "sops_secrets" {
    source_file = "env/secrets.enc.json"
}