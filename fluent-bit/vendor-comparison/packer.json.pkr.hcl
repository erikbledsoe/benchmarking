variable "image_name" {
  type    = string
  default = "calyptia-vendor-comparison-ubuntu-2004"
}

variable "image_family" {
  type    = string
  default = "calyptia-vendor-comparison"
}

variable "gcp_project_id" {
  type        = string
  default     = "calyptia-infra"
  description = "ID of the Project in Google Cloud"
}

# https://www.packer.io/docs/datasources/amazon/ami
data "amazon-ami" "base_image" {
  filters = {
    name                = "ubuntu/images/*ubuntu-focal-20.04-amd64-server-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["099720109477"]
  region      = "us-east-1"
}

source "amazon-ebs" "calyptia_vendor_comparison" {
  ami_name                    = var.image_name
  associate_public_ip_address = true
  instance_type               = "t2.micro"
  region                      = "us-east-1"
  source_ami                  = data.amazon-ami.base_image.id
  ssh_username                = "ubuntu"

  ami_groups = [
    # This causes the ami to be publicly-accessable.
    # "all",
  ]
}

source "googlecompute" "calyptia_vendor_comparison" {
  image_family        = var.image_family
  image_name          = var.image_name
  image_description   = "Comparison of various tools"
  machine_type        = "n1-standard-1"
  project_id          = var.gcp_project_id
  source_image_family = "ubuntu-2004-lts"
  ssh_username        = "ubuntu"
  zone                = "us-east1-c"
  disk_size           = "250"
}

build {

  sources = ["source.amazon-ebs.calyptia_vendor_comparison", "source.googlecompute.calyptia_vendor_comparison"]

  provisioner "shell" {
    inline = ["/usr/bin/cloud-init status --wait"]
  }

  provisioner "shell" {
    execute_command = "echo 'packer' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    script          = "./scripts/provision.sh"
  }

  provisioner "file" {
    destination = "/etc/calyptia-fluent-bit/"
    source      = "./config/calyptia/"
  }

  # For now we copy the same config to OSS
  provisioner "file" {
    destination = "/etc/fluent-bit/"
    source      = "./config/calyptia/"
  }

  provisioner "file" {
    destination = "/opt/crible/local/cribl/"
    source      = "./config/cribl/"
  }

  provisioner "file" {
    destination = "/etc/logstash/"
    source      = "./config/logstash/"
  }

  provisioner "file" {
    destination = "/etc/vector/"
    source      = "./config/vector/"
  }

  provisioner "file" {
    destination = "/opt/observiq/stanza/"
    source      = "./config/stanza/"
  }

  provisioner "file" {
    destination = "/test/"
    source      = "./config/test/"
  }

  provisioner "file" {
    destination = "/opt/fluent-bit-devtools/monitoring/"
    source      = "./config/monitoring/"
  }

  # Provide various metadata from Packer we can use
  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
