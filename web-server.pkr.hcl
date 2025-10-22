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
  ssh_username  = "ec2-user"
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
      "sudo chown ec2-user:ec2-user /tmp/web-source"
    ]
  }

  provisioner "file" {
    source      = "./"
    destination = "/tmp/web-source"
  }

  provisioner "shell" {
    inline = [
      "sudo -u ec2-user bash -c '",
      "  export NVM_DIR=\"$HOME/.nvm\"",
      "  [ -s \"$NVM_DIR/nvm.sh\" ] && . \"$NVM_DIR/nvm.sh\"",
      "",
      "  cd /tmp/web-source",
      "  echo \"Running npm install and build...\"",
      "  npm install",
      "  npm run build",
      "'",

      "sudo mkdir -p /home/ec2-user/web-server/build",
      "sudo chown -R ec2-user:ec2-user /home/ec2-user/web-server",
      "sudo rsync -a --delete /tmp/web-source/build/ /home/ec2-user/web-server/build/",
      "sudo cp /tmp/web-source/nginx.conf /etc/nginx/nginx.conf",
      
      "sudo chmod 755 /home/ec2-user",
      "sudo chmod -R 755 /home/ec2-user/web-server/build",

      "echo '--- Running nslookup for DNS debugging ---'",
      "nslookup internal-WAS-LB-1905652051.ap-northeast-2.elb.amazonaws.com || echo 'nslookup command failed'",
      "echo '--- End of DNS debugging ---'",
      "echo 'Testing nginx configuration'",
      "sudo nginx -t",
      "echo 'Restarting nginx'",
      "sudo systemctl restart nginx"
    ]
  }
}
