# Tell terraform to use the provider and select a version.
terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.60.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    tls = {
      source = "hashicorp/tls"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.2"
    }
    local = {
      source = "hashicorp/local"
    }
  }
}

variable "server_type_small" {
  type    = string
  default = "cx23"
}

variable "server_type_big" {
  type    = string
  default = "cx33"
}

variable "location" {
  type    = string
  default = "fsn1" # Falkenstein
  # default = "hel1" # Helsinki
  # default = "nbg1" # Nuremberg
}

variable "hcloud_token" {
  sensitive = true
}

variable "github_token" {
  sensitive = true
}


# Configure the Hetzner Cloud Provider
provider "hcloud" {
  token = var.hcloud_token
}

provider "github" {
  token = var.github_token
}

# Знаходимо наш Packer snapshot за label — terraform сам підхопить останню версію
data "hcloud_image" "k8s_node" {
  with_selector = "type=k8s-node"
  most_recent   = true
}

resource "hcloud_network" "k8s" {
  ip_range = "10.0.0.0/16"
  name     = "k8s"
}

resource "hcloud_network_subnet" "k8s-subnet" {
  ip_range     = "10.0.1.0/24"
  network_id   = hcloud_network.k8s.id
  network_zone = "eu-central"
  type         = "cloud"
}

resource "hcloud_firewall" "myfirewall" {
  name = "my-firewall"
  rule {
    direction = "in"
    protocol  = "icmp"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "6443"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
}

resource "hcloud_server" "master" {
  name         = "master"
  image        = data.hcloud_image.k8s_node.id
  server_type  = var.server_type_small
  location     = var.location
  firewall_ids = [hcloud_firewall.myfirewall.id]
  user_data    = file("cloud-init.sh")
  ssh_keys     = [hcloud_ssh_key.main.id]
  labels = {
    "test" : "master"
  }

  lifecycle {
    ignore_changes = [ssh_keys]
  }
}

resource "hcloud_server" "spark" {
  name         = "spark"
  image        = data.hcloud_image.k8s_node.id
  server_type  = var.server_type_big
  location     = var.location
  firewall_ids = [hcloud_firewall.myfirewall.id]
  user_data    = file("cloud-init.sh")
  ssh_keys     = [hcloud_ssh_key.main.id]
  labels = {
    "test" : "spark"
  }

  lifecycle {
    ignore_changes = [ssh_keys]
  }
}

resource "hcloud_server" "trino" {
  name         = "trino"
  image        = data.hcloud_image.k8s_node.id
  server_type  = var.server_type_big
  location     = var.location
  firewall_ids = [hcloud_firewall.myfirewall.id]
  user_data    = file("cloud-init.sh")
  ssh_keys     = [hcloud_ssh_key.main.id]
  labels = {
    "test" : "trino"
  }

  lifecycle {
    ignore_changes = [ssh_keys]
  }
}

resource "hcloud_server" "kafka" {
  name         = "kafka"
  image        = data.hcloud_image.k8s_node.id
  server_type  = var.server_type_small
  location     = var.location
  firewall_ids = [hcloud_firewall.myfirewall.id]
  user_data    = file("cloud-init.sh")
  ssh_keys     = [hcloud_ssh_key.main.id]
  labels = {
    "test" : "kafka"
  }

  lifecycle {
    ignore_changes = [ssh_keys]
  }
}

resource "hcloud_server" "airflow" {
  name         = "airflow"
  image        = data.hcloud_image.k8s_node.id
  server_type  = var.server_type_small
  location     = var.location
  firewall_ids = [hcloud_firewall.myfirewall.id]
  user_data    = file("cloud-init.sh")
  ssh_keys     = [hcloud_ssh_key.main.id]
  labels = {
    "test" : "airflow"
  }

  lifecycle {
    ignore_changes = [ssh_keys]
  }
}

resource "hcloud_server_network" "master" {
  server_id  = hcloud_server.master.id
  network_id = hcloud_network.k8s.id
}

resource "hcloud_server_network" "spark" {
  server_id  = hcloud_server.spark.id
  network_id = hcloud_network.k8s.id
}

resource "hcloud_server_network" "trino" {
  server_id  = hcloud_server.trino.id
  network_id = hcloud_network.k8s.id
}

resource "hcloud_server_network" "kafka" {
  server_id  = hcloud_server.kafka.id
  network_id = hcloud_network.k8s.id
}

resource "hcloud_server_network" "airflow" {
  server_id  = hcloud_server.airflow.id
  network_id = hcloud_network.k8s.id
}

resource "tls_private_key" "deploy" {
  algorithm = "ED25519"

  lifecycle {
    ignore_changes = all
  }
}

resource "local_file" "deploy_key" {
  content         = tls_private_key.deploy.private_key_openssh
  filename        = pathexpand("~/.ssh/hc_deploy")
  file_permission = "0600"

  lifecycle {
    ignore_changes = all
  }
}

resource "local_file" "deploy_key_pub" {
  content         = tls_private_key.deploy.public_key_openssh
  filename        = pathexpand("~/.ssh/hc_deploy.pub")
  file_permission = "0644"

  lifecycle {
    ignore_changes = all
  }
}

resource "hcloud_ssh_key" "main" {
  name       = "my-ssh-key"
  public_key = tls_private_key.deploy.public_key_openssh

  lifecycle {
    ignore_changes = all
  }
}

resource "github_actions_secret" "ssh_private_key" {
  repository      = "data-project"
  secret_name     = "SSH_PRIVATE_KEY"
  plaintext_value = tls_private_key.deploy.private_key_openssh
}

resource "null_resource" "k8s_cluster" {
  depends_on = [
    hcloud_server_network.master,
    hcloud_server_network.spark,
    hcloud_server_network.trino,
    hcloud_server_network.kafka,
    hcloud_server_network.airflow,
  ]

  triggers = {
    master_id = hcloud_server.master.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      MASTER_PUB="${hcloud_server.master.ipv4_address}"
      MASTER_PRIV="${hcloud_server_network.master.ip}"
      SSH="ssh -i ~/.ssh/hc_deploy -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes root@"

      # pub:priv пари для воркерів
      WORKERS_MAP="${hcloud_server.spark.ipv4_address}:${hcloud_server_network.spark.ip} ${hcloud_server.trino.ipv4_address}:${hcloud_server_network.trino.ip} ${hcloud_server.kafka.ipv4_address}:${hcloud_server_network.kafka.ip} ${hcloud_server.airflow.ipv4_address}:${hcloud_server_network.airflow.ip}"
      WORKERS="${hcloud_server.spark.ipv4_address} ${hcloud_server.trino.ipv4_address} ${hcloud_server.kafka.ipv4_address} ${hcloud_server.airflow.ipv4_address}"

      # -----------------------------------------------------------------------
      # 1. Чекаємо реальної SSH автентифікації на всіх нодах
      #    Перевіряємо не просто відкритий порт, а саме що ключ приймається.
      #    apt-get upgrade може перезапустити SSH — тому робимо retry.
      # -----------------------------------------------------------------------
      for IP in $MASTER_PUB $WORKERS; do
        echo "Waiting for SSH auth on $IP..."
        for i in $(seq 1 60); do
          $SSH$IP "echo ok" 2>/dev/null && echo "$IP is ready" && break
          echo "  attempt $i/60..."
          sleep 10
        done
        ssh-keyscan -H "$IP" >> ~/.ssh/known_hosts 2>/dev/null || true
      done

      # -----------------------------------------------------------------------
      # 2. Чекаємо завершення cloud-init на всіх нодах
      # -----------------------------------------------------------------------
      for IP in $MASTER_PUB $WORKERS; do
        echo "Waiting for cloud-init on $IP..."
        $SSH$IP "cloud-init status --wait || true"
      done

      # -----------------------------------------------------------------------
      # 3. kubeadm init на master
      #    --pod-network-cidr=10.244.0.0/16 — для Flannel CNI
      #    --apiserver-advertise-address — приватний IP (внутрішня мережа нод)
      # -----------------------------------------------------------------------
      echo "Initializing Kubernetes control plane on $MASTER_PUB..."
      $SSH$MASTER_PUB "echo 'KUBELET_EXTRA_ARGS=--node-ip=$MASTER_PRIV' > /etc/default/kubelet"
      $SSH$MASTER_PUB "kubeadm init \
        --pod-network-cidr=10.244.0.0/16 \
        --apiserver-advertise-address=$MASTER_PRIV \
        --apiserver-cert-extra-sans=$MASTER_PUB"

      # -----------------------------------------------------------------------
      # 4. Налаштовуємо kubeconfig для root на master
      # -----------------------------------------------------------------------
      $SSH$MASTER_PUB "mkdir -p /root/.kube && cp /etc/kubernetes/admin.conf /root/.kube/config"

      # -----------------------------------------------------------------------
      # 5. Встановлюємо Flannel CNI
      #    Flannel — простий overlay network для pod-to-pod комунікації
      # -----------------------------------------------------------------------
      echo "Installing Flannel CNI..."
      $SSH$MASTER_PUB "kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"

      # -----------------------------------------------------------------------
      # 6. Отримуємо команду для join workers
      # -----------------------------------------------------------------------
      JOIN_CMD=$($SSH$MASTER_PUB "kubeadm token create --print-join-command")

      # -----------------------------------------------------------------------
      # 7. Приєднуємо worker ноди — з node-ip щоб kubelet використовував приватний IP
      #    Без цього API server тягнеться до kubelet через публічний IP:10250 → заблоковано
      # -----------------------------------------------------------------------
      for PAIR in $WORKERS_MAP; do
        PUB=$(echo $PAIR | cut -d: -f1)
        PRIV=$(echo $PAIR | cut -d: -f2)
        echo "Joining worker $PUB (private: $PRIV) to cluster..."
        $SSH$PUB "echo 'KUBELET_EXTRA_ARGS=--node-ip=$PRIV' > /etc/default/kubelet"
        $SSH$PUB "$JOIN_CMD"
      done

      echo "Kubernetes cluster is ready!"
      echo "Connect: ssh -i ~/.ssh/hc_deploy root@$MASTER_PUB"
      echo "Check:   kubectl get nodes"
    EOT
  }
}

resource "null_resource" "kubeconfig" {
  depends_on = [null_resource.k8s_cluster]

  triggers = {
    master_ip = hcloud_server.master.ipv4_address
  }

  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ~/.kube
      scp -i ~/.ssh/hc_deploy -o StrictHostKeyChecking=no \
        root@${hcloud_server.master.ipv4_address}:/root/.kube/config ~/.kube/config
      sed -i '' \
        "s|server: https://[0-9.]*:6443|server: https://${hcloud_server.master.ipv4_address}:6443|" \
        ~/.kube/config
      echo "kubeconfig updated — master: ${hcloud_server.master.ipv4_address}"
    EOT
  }
}

resource "null_resource" "github_kubeconfig" {
  depends_on = [null_resource.kubeconfig]

  triggers = {
    master_ip = hcloud_server.master.ipv4_address
  }

  provisioner "local-exec" {
    command = "gh secret set KUBECONFIG --repo vsvizhak/data-project < ~/.kube/config"
  }
}

resource "null_resource" "helm_deploy" {
  depends_on = [null_resource.kubeconfig]

  triggers = {
    master_ip = hcloud_server.master.ipv4_address
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl delete job minio-init airflow-init flyway -n data-platform --ignore-not-found=true
      helm upgrade --install data-platform ${path.module}/../../k8s \
        --namespace data-platform \
        --create-namespace \
        -f ${path.module}/../../k8s/values.secret.yaml
    EOT
  }
}
