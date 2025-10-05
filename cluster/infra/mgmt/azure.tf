locals {
    location = "Central US"
}

data "azurerm_resource_group" "rg" {
  name = "gustend-mgmt"
}

data "azurerm_client_config" "current" {}


resource "azurerm_key_vault" "kv" {
  name = "gustend-mgmt"
  resource_group_name = data.azurerm_resource_group.rg.name
  location = local.location
  tenant_id = data.azurerm_client_config.current.tenant_id

  sku_name = "standard"
}

resource "azurerm_key_vault_key" "sops-key" {
    name         = "sops-key"
  key_vault_id = azurerm_key_vault.kv.id
  key_type     = "RSA"
  key_size     = 4096

  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey",
  ]
}


import {
    to = azurerm_key_vault.kv
    id = "/subscriptions/1d68b170-4207-426d-bd03-580077f57234/resourceGroups/gustend-mgmt/providers/Microsoft.KeyVault/vaults/gustend-mgmt"
}
import {
    to = azurerm_key_vault_key.sops-key
    id = "https://gustend-mgmt.vault.azure.net/keys/sops-key/5f16ea9e07e34c8a8258484924a6f1be"
}