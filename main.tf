provider "aws" {
  region = "us-east-2"
  profile = "default"
}

terraform {
  backend "s3" {
    profile = "default"
    bucket = "terraformstatecode"
    key = "task/terraform.tfstate"
    region = "us-east-2"
    
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "my-test-vpc"
  }
}

# Creating Internet Gateway

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "my-test-igw"
  }
}


# Public Route Table

resource "aws_default_route_table" "public_route" {
   default_route_table_id = aws_vpc.main.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "my-test-public-route"
  }
}

# Private Route Table

resource "aws_route_table" "private_route" {
  vpc_id = aws_vpc.main.id

  route {
    nat_gateway_id = aws_nat_gateway.my-test-nat-gateway.id
    cidr_block     = "0.0.0.0/0"
  }

  tags = {
    Name = "my-test-private-route"
  }
}

# Public Subnet
resource "aws_subnet" "public_subnet" {
  count                   = 3
  cidr_block              = var.public_cidrs[count.index]
  vpc_id                  = aws_vpc.main.id
  map_public_ip_on_launch = true
  availability_zone       = var.aws_az[count.index]

  tags = {
    Name = "my-test-public-subnet_${count.index + 1}"
  }
}

# Private Subnet
resource "aws_subnet" "private_subnet" {
  count             = 2
  cidr_block        = var.private_cidrs[count.index]
  vpc_id            = aws_vpc.main.id
  availability_zone = var.aws_az[count.index]

  tags = {
    Name = "my-test-private-subnet_${count.index + 1}"
  }
}

# elastic ip for nat gateway
resource "aws_eip" "my-test-eip" {
  vpc = true
}
# creating NAT gateway
resource "aws_nat_gateway" "my-test-nat-gateway" {
  allocation_id = aws_eip.my-test-eip.id
  subnet_id     = aws_subnet.public_subnet.0.id
}

# Associate Public Subnet with Public Route Table
resource "aws_route_table_association" "public_subnet_assoc" {
  count          = 3
  route_table_id = aws_default_route_table.public_route.id
  subnet_id      = aws_subnet.public_subnet.*.id[count.index]
}

# Associate Private Subnet with Private Route Table
resource "aws_route_table_association" "private_subnet_assoc" {
  count          = 2
  route_table_id = aws_route_table.private_route.id
  subnet_id      = aws_subnet.private_subnet.*.id[count.index]
}

# Security Group Creation
resource "aws_security_group" "test_sg" {
  name   = "my-test-sg"
  vpc_id = aws_vpc.main.id
}

# Ingress Security Port 22
resource "aws_security_group_rule" "ssh_inbound_access" {
  from_port         = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.test_sg.id
  to_port           = 22
  type              = "ingress"
  cidr_blocks       = [aws_vpc.main.cidr_block]
}



# All OutBound Access
resource "aws_security_group_rule" "all_outbound_access" {
  from_port         = 0
  protocol          = "-1"
  security_group_id = aws_security_group.test_sg.id
  to_port           = 0
  type              = "egress"
  cidr_blocks       = ["0.0.0.0/0"]
}


# ec2 instances creation

resource "aws_instance" "testserver" {
    count = 3
    ami = var.ami
    instance_type = var.instance_type
    subnet_id = aws_subnet.public_subnet.*.id[count.index]
    key_name = "devops"
    map_public_ip_on_launch = false

    user_data = <<-EOF
        #! /bin/bash
        sudo apt-get update
        sudo apt-get install -y nginx
        sudo systemctl start nginx
        sudo systemctl enable nginx
     EOF

    tags = {
        Name = "testserver_${count.index+1}"
    }
}


resource "aws_lb_target_group" "test-target-gp" {
  name     = "test-alb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

}

resource "aws_lb_target_group_attachment" "test" {
  count = 3
  target_group_arn = aws_lb_target_group.test-target-gp.arn
  target_id        = aws_instance.testserver.*.id[count.index]
  port             = 80
}




resource "aws_lb" "test-alb" {
  internal           = false
  load_balancer_type = "application"
  subnets            = aws_subnet.public_subnet.*.id
  #availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]

  
  tags = {
    Name = "test-alb"
  }
}

resource "aws_alb_listener" "test-" {
  load_balancer_arn = aws_lb.test-alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.test-target-gp.arn
  }
}


