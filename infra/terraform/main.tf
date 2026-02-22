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

variable "server_type" {
  type    = string
  default = "cax41" #arm 16 cpu 32 gb 320 ssd
  # default = "cax11" #arm 2 cpu 4 gb 40 ssd
}

variable "location" {
  type    = string
  default = "hel1" # Helsinki
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

resource "hcloud_server" "server_test" {
  name         = "test-server"
  image        = "ubuntu-24.04"
  server_type  = var.server_type
  location     = var.location
  firewall_ids = [hcloud_firewall.myfirewall.id]
  ssh_keys     = [hcloud_ssh_key.main.id]
  labels = {
    "test" : "test"
  }

  lifecycle {
    ignore_changes = [ssh_keys]
  }
}

resource "null_resource" "configure" {
  depends_on = [hcloud_server.server_test]

  triggers = {
    server_ip = hcloud_server.server_test.ipv4_address
  }

  provisioner "local-exec" {
    command = <<EOT
      set -e
      IP=${hcloud_server.server_test.ipv4_address}

      # remove old key if exists
      ssh-keygen -R "$IP" || true

      # wait for SSH to be reachable
      for i in $(seq 1 60); do
        nc -z -w 2 "$IP" 22 && echo "SSH is up" && break
        echo "Waiting for SSH... ($i/60)"
        sleep 2
      done
      nc -z -w 2 "$IP" 22

      # add current host key (non-interactive)
      ssh-keyscan -H "$IP" >> ~/.ssh/known_hosts 2>/dev/null || true

      EXTRA_VARS="$(grep -v '^#' ../../app/.env | grep '=' | sed 's/=\(.*\)/="\1"/' | tr '\n' ' ')"

      cd ../ansible

      ansible-playbook -i "$IP," \
        -u root --private-key ~/.ssh/hc_deploy \
        --extra-vars "$EXTRA_VARS" \
        site.yml
    EOT
  }
}
