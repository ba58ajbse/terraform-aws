terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }
  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "default"
  region  = "ap-northeast-1"
}

# VPC
resource "aws_vpc" "tf_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = "true"
  enable_dns_hostnames = "true"
  instance_tenancy     = "default"
  tags = {
    Name = "tf-vpc"
  }
}

# EIP
resource "aws_eip" "elastic_ip" {
  vpc = true
}

# Internet Gateway
resource "aws_internet_gateway" "tf_gw" {
  vpc_id = aws_vpc.tf_vpc.id
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.elastic_ip.id
  subnet_id     = aws_subnet.tf_public.id
}

# Subnet
resource "aws_subnet" "tf_public" {
  vpc_id            = aws_vpc.tf_vpc.id
  cidr_block        = "10.0.0.0/24"
  availability_zone = "ap-northeast-1a"

  tags = {
    Name = "tf-public"
  }
}

resource "aws_subnet" "tf_private_1" {
  vpc_id            = aws_vpc.tf_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-northeast-1a"

  tags = {
    Name = "tf-private-1"
  }
}

resource "aws_subnet" "tf_private_2" {
  vpc_id            = aws_vpc.tf_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-northeast-1c"

  tags = {
    Name = "tf-private-2"
  }
}

# Route
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.tf_vpc.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.tf_vpc.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.tf_public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private1" {
  subnet_id      = aws_subnet.tf_private_1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private2" {
  subnet_id      = aws_subnet.tf_private_2.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  gateway_id             = aws_internet_gateway.tf_gw.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route" "private" {
  route_table_id         = aws_route_table.private.id
  gateway_id             = aws_nat_gateway.nat_gateway.id
  destination_cidr_block = "0.0.0.0/0"
}

# Security Group
resource "aws_security_group" "tf_security_group" {
  name        = "tf-webserver-sg"
  description = "terraform security group"
  vpc_id      = aws_vpc.tf_vpc.id
}

resource "aws_security_group_rule" "ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.tf_security_group.id
  description       = "for EC2 instance by ssh"
}

resource "aws_security_group_rule" "web" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.tf_security_group.id
  description       = "for webserver by http"
}

resource "aws_security_group_rule" "web_outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.tf_security_group.id
}

# database
resource "aws_security_group" "db_sg" {
  name        = "tf-db-sg"
  description = "terraform security group for db"
  vpc_id      = aws_vpc.tf_vpc.id
}

resource "aws_security_group_rule" "db_inbound" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.tf_security_group.id
  security_group_id        = aws_security_group.db_sg.id
}

resource "aws_security_group_rule" "db_outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.db_sg.id
}

resource "aws_db_subnet_group" "main" {
  name        = "tf-db-subnet-group"
  description = "tf db subnet group"
  subnet_ids  = [aws_subnet.tf_private_1.id, aws_subnet.tf_private_2.id]
}

# EC2 instance
data "aws_ssm_parameter" "amzn2_ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

resource "aws_instance" "web" {
  ami                         = data.aws_ssm_parameter.amzn2_ami.value
  instance_type               = "t2.micro"
  key_name                    = "tf_ec2_key"
  subnet_id                   = aws_subnet.tf_public.id
  vpc_security_group_ids      = [aws_security_group.tf_security_group.id]
  associate_public_ip_address = true

  tags = {
    Name = "web instance"
  }
}

# key
resource "aws_key_pair" "ec2" {
  key_name   = "tf_ec2_key"
  public_key = file("~/.ssh/tf_ec2_key.pub")
}

# RDS
resource "aws_db_instance" "mariadb" {
  allocated_storage       = "10"
  identifier              = "tf-db-instance"
  engine                  = "mariadb"
  engine_version          = "10.4"
  instance_class          = "db.t2.micro"
  username                = "tf_user"
  password                = "terraform"
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.db_sg.id]
  backup_retention_period = 0
  skip_final_snapshot     = true
}
