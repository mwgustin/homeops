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