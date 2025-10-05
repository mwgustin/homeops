data "tfe_workspace" "mgmt" {
    name = "gustend-mgmt"
    organization = "gustend"
}

data "tfe_workspace" "main" {
    name = "gustend-main"
    organization = "gustend"
}

locals {
    workspaces = {
        mgmt = data.tfe_workspace.mgmt.id
        main = data.tfe_workspace.main.id
    }
}

resource "tfe_variable" "AZURE_CLIENT_ID" {
    for_each = local.workspaces
    key = "AZURE_CLIENT_ID"
    value = data.sops_file.sops_secrets.data["AZURE_CLIENT_ID"]
    category = "env"
    sensitive = false
    workspace_id = each.value
}

resource "tfe_variable" "AZURE_CLIENT_SECRET" {
    for_each = local.workspaces
    key = "AZURE_CLIENT_SECRET"
    value = data.sops_file.sops_secrets.data["AZURE_CLIENT_SECRET"]
    category = "env"
    sensitive = true
    workspace_id = each.value
}

resource "tfe_variable" "AZURE_TENANT_ID" {
    for_each = local.workspaces
    key = "AZURE_TENANT_ID"
    value = data.sops_file.sops_secrets.data["AZURE_TENANT_ID"]
    category = "env"
    sensitive = false
    workspace_id = each.value
}

resource "tfe_variable" "AZURE_SUBSCRIPTION_ID" {
    for_each = local.workspaces
    key = "AZURE_SUBSCRIPTION_ID"
    value = data.sops_file.sops_secrets.data["AZURE_SUBSCRIPTION_ID"]
    category = "env"
    sensitive = false
    workspace_id = each.value
}

resource "tfe_variable" "ARM_CLIENT_ID" {
    for_each = local.workspaces
    key = "ARM_CLIENT_ID"
    value = data.sops_file.sops_secrets.data["ARM_CLIENT_ID"]
    category = "env"
    sensitive = false
    workspace_id = each.value
}

resource "tfe_variable" "ARM_CLIENT_SECRET" {
    for_each = local.workspaces
    key = "ARM_CLIENT_SECRET"
    value = data.sops_file.sops_secrets.data["ARM_CLIENT_SECRET"]
    category = "env"
    sensitive = true
    workspace_id = each.value
}

resource "tfe_variable" "ARM_TENANT_ID" {
    for_each = local.workspaces
    key = "ARM_TENANT_ID"
    value = data.sops_file.sops_secrets.data["ARM_TENANT_ID"]
    category = "env"
    sensitive = false
    workspace_id = each.value
}

resource "tfe_variable" "ARM_SUBSCRIPTION_ID" {
    for_each = local.workspaces
    key = "ARM_SUBSCRIPTION_ID"
    value = data.sops_file.sops_secrets.data["ARM_SUBSCRIPTION_ID"]
    category = "env"
    sensitive = false
    workspace_id = each.value
}

resource "tfe_variable" "TFE_TOKEN" {
    key = "TFE_TOKEN"
    value = data.sops_file.sops_secrets.data["TFE_TOKEN"]
    category = "env"
    sensitive = true
    workspace_id = data.tfe_workspace.mgmt.id
}
