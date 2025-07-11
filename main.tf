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
  cidr_block     = "10.0.0.0/16"
  compartment_id = var.compartment_ocid
  display_name   = "tf-vcn"
}


resource "oci_core_internet_gateway" "ig" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.vcn.id
  display_name   = "tf-ig"
  # is_enabled     = true
}

resource "oci_core_route_table" "rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.vcn.id
  display_name   = "tf-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.ig.id
  }
}

resource "oci_core_security_list" "sec_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.vcn.id
  display_name   = "tf-sec-list"

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"

    tcp_options {
      min = 22
      max = 22
    }
  }

  egress_security_rules {
    protocol = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_subnet" "subnet" {
  compartment_id      = var.compartment_ocid
  vcn_id              = oci_core_virtual_network.vcn.id
  cidr_block          = "10.0.1.0/24"
  display_name        = "tf-subnet"
  route_table_id      = oci_core_route_table.rt.id
  security_list_ids   = [oci_core_security_list.sec_list.id]
  prohibit_public_ip_on_vnic = false
}

resource "oci_core_instance" "vm" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  shape               = "VM.Standard.E2.1.Micro"

  create_vnic_details {
    subnet_id        = oci_core_subnet.subnet.id
    assign_public_ip = true
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.oracle_linux.id
  }

  display_name = "tf-vm"
  metadata = {
    ssh_authorized_keys = file("~/.ssh/id_rsa.pub") # adjust path to your key
  }
}


data "oci_core_images" "oracle_linux" {
  compartment_id = var.compartment_ocid
  operating_system = "Oracle Linux"
  operating_system_version = "8"
  shape = "VM.Standard.E2.1.Micro"
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}