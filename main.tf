#export AWS_ACCESS_KEY_ID="TU_ACCESS_KEY_DE_IAM"
#export AWS_SECRET_ACCESS_KEY="TU_SECRET_KEY_DE_IAM"
#export AWS_REGION="us-east-1"

#terraform init
#terraform plan
#terraform apply -auto-approve

# 2. Obtener la URL pública
#terraform output app_url

# 3. Probar (reemplaza con tu URL)
#curl http://tu-load-balancer-dns.com

# 4. Ver los outputs completos
#terraform output

terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  # Las credenciales se leen automáticamente del entorno
}

# ==========================================
# DATA SOURCES (necesarios para VPC y subnets)
# ==========================================
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ==========================================
# 1. ECR & ECS (Contenedores)
# ==========================================
resource "aws_ecr_repository" "app_repo" {
  name                 = "bash-app-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecs_cluster" "main" {
  name = "bash-app-cluster"
}

resource "aws_ecs_task_definition" "app_task" {
  family                   = "bash-app-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "bash-app"
      image     = "${aws_ecr_repository.app_repo.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]
    }
  ])
}

# ==========================================
# 2. SECURITY GROUP (Corregido para HTTP 80)
# ==========================================
resource "aws_security_group" "ecs_sg" {
  name        = "bash-app-ecs-sg"
  description = "Permitir trafico HTTP y puerto del contenedor"
  vpc_id      = data.aws_vpc.default.id

  # Regla para que el Load Balancer reciba tráfico de internet
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Regla para el contenedor internamente
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ==========================================
# 3. LOAD BALANCER
# ==========================================
resource "aws_lb" "app_lb" {
  name               = "bash-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs_sg.id]
  subnets            = data.aws_subnets.default.ids

  tags = {
    Name = "bash-app-lb"
  }
}

resource "aws_lb_target_group" "app_tg" {
  name        = "bash-app-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
  }

  depends_on = [aws_lb.app_lb]

  tags = {
    Name = "bash-app-tg"
  }
}

resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# ==========================================
# 4. ECS SERVICE (Fargate)
# ==========================================
resource "aws_ecs_service" "app_service" {
  name            = "bash-app-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app_tg.arn
    container_name   = "bash-app"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.app_listener]

  tags = {
    Name = "bash-app-service"
  }
}

# ==========================================
# 5. ROLES IAM (Para Fargate)
# ==========================================
resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name = "ecs-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# ==========================================
# OUTPUTS
# ==========================================
output "ecr_repository_url" {
  description = "URL del registro ECR en AWS"
  value       = aws_ecr_repository.app_repo.repository_url
}

output "ecs_cluster_name" {
  description = "Nombre del cluster ECS"
  value       = aws_ecs_cluster.main.name
}

output "load_balancer_dns" {
  description = "DNS del Load Balancer para acceder a la aplicación"
  value       = aws_lb.app_lb.dns_name
}

output "app_url" {
  description = "URL pública completa para probar la aplicación"
  value       = "http://${aws_lb.app_lb.dns_name}"
}