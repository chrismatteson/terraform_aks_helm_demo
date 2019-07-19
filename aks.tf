# Generate random project name
resource "random_id" "project_name" {
  byte_length = 4
  prefix      = "CM"
}

# Generate client secret
resource "random_id" "client_secret" {
  byte_length = 32
}

# Local for tag to attach to all items
locals {
  tags = "${merge(var.tags, map("ProjectName", random_id.project_name.hex))}"
}

resource "azurerm_resource_group" "k8s" {
  name     = "${random_id.project_name.hex}-rg"
  location = "${var.location}"
  tags     = "${local.tags}"
}

resource "azurerm_azuread_application" "k8s" {
  name = "${random_id.project_name.hex}-k8s"
}

resource "azurerm_azuread_service_principal" "k8s" {
  application_id = "${azurerm_azuread_application.k8s.application_id}"
}

resource "azurerm_azuread_service_principal_password" "k8s" {
  service_principal_id = "${azurerm_azuread_service_principal.k8s.id}"
  value                = "${random_id.client_secret.id}"
  end_date             = "2020-01-01T01:02:03Z"
}

resource "azurerm_log_analytics_workspace" "k8s" {
  name                = "${random_id.project_name.hex}-aw"
  location            = "${azurerm_resource_group.k8s.location}"
  resource_group_name = "${azurerm_resource_group.k8s.name}"
  sku                 = "${var.log_analytics_workspace_sku}"
}

resource "azurerm_log_analytics_solution" "k8s" {
  solution_name         = "ContainerInsights"
  location              = "${azurerm_log_analytics_workspace.k8s.location}"
  resource_group_name   = "${azurerm_resource_group.k8s.name}"
  workspace_resource_id = "${azurerm_log_analytics_workspace.k8s.id}"
  workspace_name        = "${azurerm_log_analytics_workspace.k8s.name}"

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/ContainerInsights"
  }
}

resource "azurerm_kubernetes_cluster" "k8s" {
  name                = "${random_id.project_name.hex}-kubernetes"
  location            = "${azurerm_resource_group.k8s.location}"
  resource_group_name = "${azurerm_resource_group.k8s.name}"
  dns_prefix          = "${random_id.project_name.hex}"

  linux_profile {
    admin_username = "ubuntu"

    ssh_key {
      key_data = "${file("${var.ssh_public_key}")}"
    }
  }

  agent_pool_profile {
    name            = "agentpool"
    count           = "${var.agent_count}"
    vm_size         = "Standard_DS1_v2"
    os_type         = "Linux"
    os_disk_size_gb = 30
  }

  service_principal {
    client_id     = "${azurerm_azuread_application.k8s.application_id}"
    client_secret = "${azurerm_azuread_service_principal_password.k8s.value}"
  }

  addon_profile {
    oms_agent {
      enabled                    = true
      log_analytics_workspace_id = "${azurerm_log_analytics_workspace.k8s.id}"
    }
  }

  tags {
    Environment = "Development"
  }
}
