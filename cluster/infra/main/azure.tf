locals {
    location = "Central US"
}

data "azurerm_resource_group" "rg" {
  name = "gustend"
}

data "azurerm_client_config" "current" {}


resource "azurerm_key_vault" "kv" {
  name = "gustend-k8s-cluster"
  resource_group_name = data.azurerm_resource_group.rg.name
  location = local.location
  tenant_id = data.azurerm_client_config.current.tenant_id

  sku_name = "standard"
}

resource "azurerm_key_vault_access_policy" "tf_cli" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge"]
  key_permissions = ["Get", "List", "Update", "Create", "Import", "Delete", "Recover", "Backup", "Restore", "Purge", "GetRotationPolicy", "SetRotationPolicy" ]
  certificate_permissions = ["Get", "List", "Update", "Create", "Import", "Delete", "Recover", "Backup", "Restore", "ManageContacts", "ManageIssuers", "GetIssuers", "ListIssuers", "SetIssuers", "DeleteIssuers"]
}

resource "azurerm_key_vault_access_policy" "k8s-sp" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = "aa2db595-b33d-4815-a0a4-09b401cb6f85"
  
  secret_permissions = ["Get", "List"]

}

resource "azurerm_key_vault_secret" "sops" {
    for_each = nonsensitive(data.sops_file.sops_secrets.data)
    name = each.key
    value = each.value
    key_vault_id = azurerm_key_vault.kv.id
}
