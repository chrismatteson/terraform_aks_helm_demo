provider "helm" {
  kubernetes {
    host     = "${azurerm_kubernetes_cluster.k8s.kube_config.0.host}"
    username = "${azurerm_kubernetes_cluster.k8s.kube_config.0.username}"
    password = "${azurerm_kubernetes_cluster.k8s.kube_config.0.password}"

    client_certificate     = "${base64decode(azurerm_kubernetes_cluster.k8s.kube_config.0.client_certificate)}"
    client_key             = "${base64decode(azurerm_kubernetes_cluster.k8s.kube_config.0.client_key)}"
    cluster_ca_certificate = "${base64decode(azurerm_kubernetes_cluster.k8s.kube_config.0.cluster_ca_certificate)}"
  }
}

resource "null_resource" "helm" {
  provisioner "local-exec" {
    command = "git clone https://github.com/hashicorp/consul-helm.git"
  }
}

resource "helm_release" "consul" {
  name       = "${random_id.project_name.hex}-consul"
  chart      = "consul-helm"
  repository = "./"
  set        = {
    name  = "ui.service.type"
    value  = "LoadBalancer"
  }
  depends_on = ["null_resource.helm"]
}
