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

import {
    to = azurerm_key_vault.kv
    id = "/subscriptions/1d68b170-4207-426d-bd03-580077f57234/resourceGroups/gustend/providers/Microsoft.KeyVault/vaults/gustend-k8s-cluster"
}

import {
    to = azurerm_key_vault_secret.sops["activity-rando-discord-server-id"]
    id = "https://gustend-k8s-cluster.vault.azure.net/secrets/activity-rando-discord-server-id/82a48626c9a04917a318e43e96cbf839"
}
import {
  to = azurerm_key_vault_secret.sops["activity-rando-sheet-id"]
  id = "https://gustend-k8s-cluster.vault.azure.net/secrets/activity-rando-sheet-id/c9d189738ace495a8b0fe92fc6999a73"
}
import {
  to = azurerm_key_vault_secret.sops["cloudflare-tunnel-credentials"]
  id = "https://gustend-k8s-cluster.vault.azure.net/secrets/cloudflare-tunnel-credentials/e10e34e25dff47ed9d322a8090529fc5"
}
import {
  to = azurerm_key_vault_secret.sops["discord-token"]
  id = "https://gustend-k8s-cluster.vault.azure.net/secrets/discord-token/8cd00117de6140ecb8e0ce0a7cf0cf1d"
}
import {
  to = azurerm_key_vault_secret.sops["foundry-admin-key"]
  id = "https://gustend-k8s-cluster.vault.azure.net/secrets/foundry-admin-key/7c199f0634764604adc36bacb140ef2d"
}
import {
  to = azurerm_key_vault_secret.sops["foundry-user-name"]
  id = "https://gustend-k8s-cluster.vault.azure.net/secrets/foundry-user-name/1bb95b99bfa541498c755d5cf5020c7a"
}
import {
  to = azurerm_key_vault_secret.sops["foundry-user-password"]
  id = "https://gustend-k8s-cluster.vault.azure.net/secrets/foundry-user-password/a5e7e98c06414d4f81c51a5c410b9978"
}
import {
  to = azurerm_key_vault_secret.sops["ghcr-dockerconfig"]
  id = "https://gustend-k8s-cluster.vault.azure.net/secrets/ghcr-dockerconfig/b741def95b0f49e6b9f0131c261dde10"
}
import {
  to = azurerm_key_vault_secret.sops["google-sa"]
  id = "https://gustend-k8s-cluster.vault.azure.net/secrets/google-sa/ead706277d2a4edfa9e2c81529631dba"
}
import {
  to = azurerm_key_vault_secret.sops["gustend-ghost-config"]
  id = "https://gustend-k8s-cluster.vault.azure.net/secrets/gustend-ghost-config/f64ca7c43d7a4b6a9dcf07f93e9a1de8"
}
import {
  to = azurerm_key_vault_secret.sops["gustend-ghost-config-mysql-pass"]
  id = "https://gustend-k8s-cluster.vault.azure.net/secrets/gustend-ghost-config-mysql-pass/2af42c6abb344cbebeda21f7c46d55b3"
}
