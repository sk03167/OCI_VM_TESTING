terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.0"
    }
  }
}


provider "oci" {
  config_file_profile = "DEFAULT"
  region              = "ap-mumbai-1"
}

variable "tenancy_ocid" {}
variable "compartment_ocid" {}

resource "oci_identity_compartment" "my_compartment" {
  name           = "my_tf_compartment"
  description    = "Created via Terraform"
  compartment_id = var.tenancy_ocid
  enable_delete  = true
}

resource "oci_core_virtual_network" "vcn" {
  compartment_id = var.compartment_ocid
  cidr_block     = "10.0.0.0/16"
  display_name   = "tf-vcn"
  dns_label      = "tfvcn"
}

resource "oci_core_internet_gateway" "internet_gateway" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.vcn.id
  display_name   = "tf-internet-gateway"
  enabled        = true
}

resource "oci_core_route_table" "public_route_table" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.vcn.id
  display_name   = "tf-public-route-table"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.internet_gateway.id
  }
}

resource "oci_core_security_list" "public_security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.vcn.id
  display_name   = "tf-public-security-list"

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"

    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"

    tcp_options {
      min = 80
      max = 80
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}


resource "oci_core_subnet" "public_subnet" {
  compartment_id      = var.compartment_ocid
  vcn_id              = oci_core_virtual_network.vcn.id
  cidr_block          = "10.0.1.0/24"
  display_name        = "tf-public-subnet"
  dns_label           = "pubsubnet"
  prohibit_public_ip_on_vnic = false  # allows assigning public IP

  route_table_id      = oci_core_route_table.public_route_table.id
  security_list_ids   = [oci_core_security_list.public_security_list.id]

  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
}

resource "oci_core_instance" "vm" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  shape               = "VM.Standard.E2.1.Micro" # Always Free eligible

  shape_config {
    ocpus         = 1
    memory_in_gbs = 1
  }

  display_name = "tf-vm"
  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.oracle_linux.images[0].id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public_subnet.id
    assign_public_ip = true
    display_name     = "vm-vnic"
    hostname_label   = "vmhost"
  }

  metadata = {
    ssh_authorized_keys = file("keys/oci_vm_key/id_ed25519.pub") # adjust path if needed
  }
}


data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "oracle_linux" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  shape                    = "VM.Standard.E2.1.Micro"
}

output "vm_public_ip" {
  value = oci_core_instance.vm.public_ip
}
