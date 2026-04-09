output "master_ip" {
  value = hcloud_server.master.ipv4_address
}

output "worker_ips" {
  value = {
    spark   = hcloud_server.spark.ipv4_address
    trino   = hcloud_server.trino.ipv4_address
    kafka   = hcloud_server.kafka.ipv4_address
    airflow = hcloud_server.airflow.ipv4_address
  }
}
