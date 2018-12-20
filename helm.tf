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

provider "kubernetes" {
  host     = "${azurerm_kubernetes_cluster.k8s.kube_config.0.host}"
  username = "${azurerm_kubernetes_cluster.k8s.kube_config.0.username}"
  password = "${azurerm_kubernetes_cluster.k8s.kube_config.0.password}"

  client_certificate     = "${base64decode(azurerm_kubernetes_cluster.k8s.kube_config.0.client_certificate)}"
  client_key             = "${base64decode(azurerm_kubernetes_cluster.k8s.kube_config.0.client_key)}"
  cluster_ca_certificate = "${base64decode(azurerm_kubernetes_cluster.k8s.kube_config.0.cluster_ca_certificate)}"
}

resource "null_resource" "helm" {
  provisioner "local-exec" {
    command = "git clone https://github.com/hashicorp/consul-helm.git"
  }
}

resource "helm_release" "consul" {
  name       = "consul-${random_id.project_name.hex}"
  chart      = "consul-helm"
  repository = "./"

  set = {
    name  = "ui.service.type"
    value = "LoadBalancer"
  }

  depends_on = ["null_resource.helm"]
}

data "kubernetes_service" "consul" {
  metadata {
    name = "${helm_release.consul.name}-ui"
  }
}

data "kubernetes_service" "postgres" {
  metadata {
    name = "${helm_release.postgres.name}-postgresql"
  }
}

resource "helm_repository" "incubator" {
  name = "incubator"
  url  = "https://kubernetes-charts-incubator.storage.googleapis.com"
}

resource "helm_release" "vault" {
  name       = "vault-${random_id.project_name.hex}"
  repository = "${helm_repository.incubator.metadata.0.name}"
  chart      = "incubator/vault"

  set = {
    name  = "vault.dev"
    value = "true"
  }

  set = {
    name  = "vault.config.storage.consul.address"
    value = "${helm_release.consul.name}:8500"
  }
}

resource "helm_release" "postgres" {
  name  = "postgres-${random_id.project_name.hex}"
  chart = "stable/postgresql"

  set = {
    name  = "postgresUser"
    value = "root"
  }

  set = {
    name  = "postgresPassword"
    value = "root"
  }

  set = {
    name  = "postgresDatabase"
    value = "rails_development"
  }
}

resource "null_resource" "vault" {
  provisioner "local-exec" {
    command = <<EOT
echo "$(terraform output kube_config)" > ./azurek8s;
export KUBECONFIG=./azurek8s;
export VAULT_POD=$(kubectl get pods --namespace default -l "app=vault" -o jsonpath="{.items[0].metadata.name}");
export VAULT_TOKEN=$(kubectl logs $VAULT_POD | grep 'Root Token' | cut -d' ' -f3);
export VAULT_ADDR=http://127.0.0.1:8200;
kubectl port-forward $VAULT_POD 8200 &
sleep 10s;
echo $VAULT_TOKEN | vault login -;
vault secrets enable database;
vault write database/config/postgres \
    plugin_name=postgresql-database-plugin \
    allowed_roles="postgres-role" \
    connection_url="postgresql://root:root@${data.kubernetes_service.postgres.spec.0.cluster_ip}:5432/rails_development?sslmode=disable";
vault write database/roles/postgres-role \
    db_name=postgres \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h";
vault policy write postgres-policy postgres-policy.hcl;
kubectl apply -f postgres-serviceaccount.yml;
export VAULT_SA_NAME=$(kubectl get sa postgres-vault -o jsonpath="{.secrets[*]['name']}");
export SA_JWT_TOKEN=$(kubectl get secret $VAULT_SA_NAME -o jsonpath="{.data.token}" | base64 --decode; echo);
export SA_CA_CRT=$(kubectl get secret $VAULT_SA_NAME -o jsonpath="{.data['ca\.crt']}" | base64 --decode; echo);
export K8S_HOST=${azurerm_kubernetes_cluster.k8s.fqdn};
vault auth enable kubernetes;
vault write auth/kubernetes/config \
  token_reviewer_jwt="$SA_JWT_TOKEN" \
  kubernetes_host="https://$K8S_HOST:443" \
  kubernetes_ca_cert="$SA_CA_CRT";
vault write auth/kubernetes/role/postgres \
    bound_service_account_names=postgres-vault \
    bound_service_account_namespaces=default \
    policies=postgres-policy \
    ttl=24h;
pkill kubectl
EOT
  }

  depends_on = ["helm_release.postgres", "helm_release.vault"]
}
