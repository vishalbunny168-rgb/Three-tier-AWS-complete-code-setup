
# =====================================================
# STEP 1: Configure AWS Provider
# This tells Terraform to use AWS and which region
# DO NOT hardcode access keys here
# Run: aws configure (on your terminal) to set keys safely
# =====================================================


provider "aws" {
  region     = "ap-south-1"
  access_key = "AKIAVFIWI6SYIZLX22AS"
  secret_key = "liPnZxATm9714QV0xcgW3yUlhUeyeLDz+97bgYzr"
}

#provider "aws" {
#  region = "ap-south-1"  # Mumbai region (closest to you)
#}

# =====================================================
# STEP 2: Get Available AZs
# This automatically picks 2 Availability Zones
# in your region for high availability
# =====================================================

data "aws_availability_zones" "available" {
  state = "available"
}

# =====================================================
# STEP 3: Create VPC (Virtual Private Cloud)
# This is your own isolated network in AWS
# Think of it as your own private building
# CIDR [IP_ADDRESS] gives you 65,536 IPs
# =====================================================

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "three-tier-vpc"
  }
}

# =====================================================
# STEP 4: Create Internet Gateway
# This is the door that connects your VPC to the internet
# Without this, nothing inside can reach the internet
# =====================================================

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "three-tier-igw"
  }
}

# =====================================================
# STEP 5: Create Public Subnets (2 AZs)
# These are the "front desk" areas where your
# web servers (ALB) sit — they CAN talk to internet
# One in each AZ for high availability
# =====================================================

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-az1"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-az2"
  }
}

# =====================================================
# STEP 6: Create Private Subnets (2 AZs)
# These are the "back rooms" where your app servers
# and database sit — they CANNOT be reached from internet
# This is a security best practice
# =====================================================

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "private-subnet-az1"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "private-subnet-az2"
  }
}

# =====================================================
# STEP 7: Create DB Subnets (2 AZs)
# Separate subnets specifically for RDS database
# RDS requires subnets in at least 2 AZs
# =====================================================

resource "aws_subnet" "db_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.5.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "db-subnet-az1"
  }
}

resource "aws_subnet" "db_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.6.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "db-subnet-az2"
  }
}

# =====================================================
# STEP 8: Create Route Table for Public Subnets
# This is like a GPS that tells traffic where to go
# Public route table sends all internet traffic (0.0.0.0/0)
# to the Internet Gateway
# =====================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# =====================================================
# STEP 9: Create Security Group for ALB
# This is the firewall for your Load Balancer
# Allows HTTP (80) and HTTPS (443) from anywhere
# =====================================================

resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP and HTTPS traffic to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-sg"
  }
}

# =====================================================
# STEP 10: Create Security Group for EC2 (App Servers)
# Only allows traffic FROM the ALB — not from internet
# This means no one can directly access your app servers
# =====================================================

resource "aws_security_group" "ec2_sg" {
  name        = "ec2-app-sg"
  description = "Allow traffic only from ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow HTTP from ALB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    description = "Allow SSH for management"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-app-sg"
  }
}

# =====================================================
# STEP 11: Create Security Group for RDS (Database)
# Only allows MySQL traffic (port 3306) FROM EC2 app servers
# Database is completely hidden from internet
# =====================================================

resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Allow MySQL traffic only from EC2 app servers"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow MySQL from EC2 only"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-sg"
  }
}

# =====================================================
# STEP 12: Get Latest Amazon Linux 2023 AMI
# This automatically finds the latest AL2023 image
# so you dont need to hardcode an AMI ID
# =====================================================

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# =====================================================
# STEP 13: Create EC2 Instances (App Servers)
# Two EC2 instances — one in each AZ
# t2.micro is free tier eligible
# User data installs Apache and creates a simple web page
# =====================================================

resource "aws_instance" "app_server_1" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_1.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello from App Server 1 - AZ1</h1><p>3-Tier Architecture by Vishal Raj</p>" > /var/www/html/index.html
              EOF

  tags = {
    Name = "app-server-az1"
  }
}

resource "aws_instance" "app_server_2" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_2.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello from App Server 2 - AZ2</h1><p>3-Tier Architecture by Vishal Raj</p>" > /var/www/html/index.html
              EOF

  tags = {
    Name = "app-server-az2"
  }
}

# =====================================================
# STEP 14: Create Application Load Balancer (ALB)
# This sits in PUBLIC subnets and distributes traffic
# evenly across your 2 app servers in both AZs
# If one AZ goes down, ALB sends all traffic to the other
# =====================================================

resource "aws_lb" "app_alb" {
  name               = "three-tier-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = {
    Name = "three-tier-alb"
  }
}

# =====================================================
# STEP 15: Create Target Group
# This is a group of EC2 instances that ALB sends traffic to
# Health checks ensure ALB only sends to healthy instances
# =====================================================

resource "aws_lb_target_group" "app_tg" {
  name     = "app-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }

  tags = {
    Name = "app-tg"
  }
}

# Register both EC2 instances to the target group
resource "aws_lb_target_group_attachment" "app_1" {
  target_group_arn = aws_lb_target_group.app_tg.arn
  target_id        = aws_instance.app_server_1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "app_2" {
  target_group_arn = aws_lb_target_group.app_tg.arn
  target_id        = aws_instance.app_server_2.id
  port             = 80
}

# =====================================================
# STEP 16: Create ALB Listener
# This listens on port 80 and forwards all traffic
# to the target group (your EC2 instances)
# =====================================================

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# =====================================================
# STEP 17: Create RDS Subnet Group
# RDS needs to know which subnets it can use
# We give it our 2 DB subnets in different AZs
# =====================================================

resource "aws_db_subnet_group" "rds_subnet" {
  name       = "rds-subnet-group"
  subnet_ids = [aws_subnet.db_1.id, aws_subnet.db_2.id]

  tags = {
    Name = "rds-subnet-group"
  }
}

# =====================================================
# STEP 18: Create RDS MySQL Database (Multi-AZ)
# This creates a MySQL database with a standby copy
# in another AZ — if one AZ fails, it auto-switches
# db.t3.micro is the smallest (cheapest) option
# =====================================================

resource "aws_db_instance" "mysql" {
  identifier             = "three-tier-db"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  storage_type           = "gp3"
  db_name                = "appdb"
  username               = "admin"
  password               = "[PASSWORD]!"  # CHANGE THIS to a strong password
  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true

  tags = {
    Name = "three-tier-rds"
  }
}

# =====================================================
# STEP 19: Outputs
# After terraform apply, these values will be printed
# The ALB DNS is the URL you use to access your app
# =====================================================

output "alb_dns_name" {
  description = "URL to access your application"
  value       = aws_lb.app_alb.dns_name
}

output "app_server_1_id" {
  description = "EC2 Instance ID of App Server 1"
  value       = aws_instance.app_server_1.id
}

output "app_server_2_id" {
  description = "EC2 Instance ID of App Server 2"
  value       = aws_instance.app_server_2.id
}

output "rds_endpoint" {
  description = "RDS Database endpoint for your app to connect"
  value       = aws_db_instance.mysql.endpoint
}

output "vpc_id" {
  description = "VPC ID of the 3-tier architecture"
  value       = aws_vpc.main.id
}

