# Tell terraform to use the provider and select a version.
terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.60.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.2"
    }
  }
}

variable "server_type" {
  type = string
  default = "cax41" #arm 16 cpu 32 gb 320 ssd
  # default = "cax11"
}

variable "hcloud_token" {
  sensitive = true
}

# Configure the Hetzner Cloud Provider
provider "hcloud" {
  token = var.hcloud_token
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

  # rule {
  #   direction = "in"
  #   protocol  = "tcp"
  #   port      = "80-85"
  #   source_ips = [
  #     "0.0.0.0/0",
  #     "::/0"
  #   ]
  # }

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

resource "hcloud_ssh_key" "main" {
  name       = "my-ssh-key"
  public_key = file("~/.ssh/hc_deploy.pub")
}

resource "hcloud_server" "server_test" {
  name        = "test-server"
  image       = "ubuntu-24.04"
  server_type = var.server_type
  location    = "nbg1"
  firewall_ids = [hcloud_firewall.myfirewall.id]
  ssh_keys    = [hcloud_ssh_key.main.id]
  labels = {
    "test" : "test"
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

      cd ../ansible
      ansible-playbook -i "$IP," \
        -u root --private-key ~/.ssh/hc_deploy \
        --extra-vars "$(grep -v '^#' ../../app/.env | grep '=' | sed 's/=\(.*\)/="\1"/' | tr '\n' ' ')" \
        site.yml
    EOT
  }
}
