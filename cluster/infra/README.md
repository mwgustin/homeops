Terraform projects to manage external resources


- mgmt
    - Management project
    - Configures TF workspaces 
    - Configures management keyvault
- main
    - Configures and manages cluster keyvault



Initialization:
There's a chicken-and-egg problem with the mgmt project.  To initialize, we must do the following steps first:

- Initialize the gustend-mgmt resource group
- Initializethe gustend-mgmt key vault and sops-key 
- Create SPN and grant it access to the subscription (and specific keyvault management permissions as well)
- Initialize the TFE workspace and use the SOPS secret variables in the workspace
- Set up import blocks for the initial variables
- Set up import blocks for the key vault and key

```
import {
  to = tfe_variable.AZURE_SUBSCRIPTION_ID["mgmt"]
  id = "<org-name>/<mgmt-workspace-name>/<variable-id>"
}
```

