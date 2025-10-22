packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "git_hash" {
  type    = string
  default = "local"
}

variable "vpc_id" {
  type    = string
  default = ""
}

variable "subnet_id" {
  type    = string
  default = ""
}

source "amazon-ebs" "web-tier" {
  region        = var.aws_region
  instance_type = "t3.small"
  ssh_username  = "ubuntu"
  vpc_id        = var.vpc_id
  subnet_id     = var.subnet_id
  associate_public_ip_address = true
  source_ami_filter {
    filters = {
      "tag:Name"          = "csm-web-tier-ami"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["self"]
  }
  ami_name = "csm-web-tier-ami-${var.git_hash}"
  tags = {
    Name       = "csm-web-tier-ami"
    GitHash    = var.git_hash
  }
}

build {
  name    = "web-tier-build"
  sources = ["source.amazon-ebs.web-tier"]

  provisioner "shell" {
    inline = [
      "sudo mkdir -p /tmp/web-source",
      "sudo chown ubuntu:ubuntu /tmp/web-source"
    ]
  }

  provisioner "file" {
    source      = "./"
    destination = "/tmp/web-source"
  }

  provisioner "shell" {
    inline = [
      "sudo -u ubuntu bash -c '",
      "  export NVM_DIR=\"$HOME/.nvm\"",
      "  [ -s \"$NVM_DIR/nvm.sh\" ] && \. \"$NVM_DIR/nvm.sh\"",
      "",
      "  cd /tmp/web-source",
      "  echo \"Running npm install and build...\"",
      "  npm install",
      "  npm run build",
      "'",

      "sudo mkdir -p /home/ubuntu/web-server/build",
      "sudo chown -R ubuntu:ubuntu /home/ubuntu/web-server",
      "sudo rsync -a --delete /tmp/web-source/build/ /home/ubuntu/web-server/build/",
      "sudo cp /tmp/web-source/nginx.conf /etc/nginx/nginx.conf",
      
      "sudo sed -i 's/user nginx;/user ubuntu;/' /etc/nginx/nginx.conf",
      "sudo sed -i 's|root    /home/ec2-user/web-server/build;|root    /home/ubuntu/web-server/build;|g' /etc/nginx/nginx.conf",

      "sudo systemctl restart nginx"
    ]
  }
}
