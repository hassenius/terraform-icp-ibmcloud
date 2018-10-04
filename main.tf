provider "ibm" {
    softlayer_username = "${var.sl_username}"
    softlayer_api_key = "${var.sl_api_key}"
}

resource "random_id" "clusterid" {
  byte_length = "4"
}

resource "tls_private_key" "installkey" {
  algorithm   = "RSA"
}

resource "tls_private_key" "registry_key" {
  algorithm = "RSA"
  rsa_bits = "4096"
}

resource "tls_self_signed_cert" "registry_cert" {
  key_algorithm   = "RSA"
  private_key_pem = "${tls_private_key.registry_key.private_key_pem}"

  subject {
    common_name  = "${var.deployment}-boot-${random_id.clusterid.hex}.${var.domain}"
  }

  dns_names  = ["${var.deployment}-boot-${random_id.clusterid.hex}.${var.domain}"]
  validity_period_hours = "${24 * 365 * 10}"

  allowed_uses = [
    "server_auth"
  ]
}

data "ibm_network_vlan" "private_vlan" {
  count = "${var.private_vlan_router_hostname != "" ? 1 : 0}"
  router_hostname = "${var.private_vlan_router_hostname}.${var.datacenter}"
  number = "${var.private_vlan_number}"
}

data "ibm_network_vlan" "public_vlan" {
  count = "${var.private_network_only != true && var.public_vlan_router_hostname != "" ? 1 : 0}"
  router_hostname = "${var.public_vlan_router_hostname}.${var.datacenter}"
  number = "${var.public_vlan_number}"
}

data "ibm_compute_ssh_key" "public_key" {
  count = "${length(var.key_name)}"
  label = "${element(var.key_name, count.index)}"
}

locals {
  docker_package_uri = "${var.docker_package_location != "" ? "/tmp/${basename(var.docker_package_location)}" : "" }"
  master_fs_ids = "${compact(
      concat(
        ibm_storage_file.fs_audit.*.id,
        ibm_storage_file.fs_registry.*.id,
        list(""))
    )}"

  # use a local private registry we stand up on the boot node if image location is specified
  inception_parts = "${split("/", var.icp_inception_image)}"
  inception_image = "${var.image_location == "" || length(local.inception_parts) == 3 ?
      "${var.icp_inception_image}" :
      "${var.deployment}-boot-${random_id.clusterid.hex}.${var.domain}/${var.icp_inception_image}" }"

  private_vlan_id = "${element(concat(data.ibm_network_vlan.private_vlan.*.id, list("-1")), 0) }"
  public_vlan_id = "${element(concat(data.ibm_network_vlan.public_vlan.*.id, list("-1")), 0)}"
}

# Generate a random string in case user wants us to generate admin password
resource "random_id" "adminpassword" {
  byte_length = "16"
}
