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
    tfe = {
        source = "hashicorp/tfe"
        version = ">= 0.54.0"
    }
  }
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "gustend"
    workspaces {
      name = "gustend-mgmt"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "sops" {}

provider tfe {}


data "sops_file" "sops_secrets" {
    source_file = "env/secrets.enc.json"
}