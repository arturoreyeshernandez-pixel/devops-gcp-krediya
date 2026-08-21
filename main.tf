terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

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



# El proveedor de AWS detecta automáticamente las variables de entorno:
# - AWS_ACCESS_KEY_ID
# - AWS_SECRET_ACCESS_KEY
# - AWS_REGION (o AWS_DEFAULT_REGION)
provider "aws" {
  # No se declaran credenciales aqui por seguridad.
  # Terraform las lee de la terminal automaticamente.
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

# 1. Repositorio ECR para guardar la imagen Docker
resource "aws_ecr_repository" "app_repo" {
  name                 = "bash-app-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# 2. Cluster ECS para ejecutar contenedores
resource "aws_ecs_cluster" "main" {
  name = "bash-app-cluster"
}

# 3. Definicion de la tarea (Task Definition) para Fargate
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

# 4. Grupo de Seguridad (Security Group) para permitir tráfico al puerto 8080
resource "aws_security_group" "ecs_sg" {
  name        = "bash-app-ecs-sg"
  description = "Permitir trafico de entrada al puerto 8080"
  vpc_id      = data.aws_vpc.default.id

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
# LOAD BALANCER (para hacerlo público)
# ==========================================

# 5. Load Balancer público
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

# 6. Target Group (conecta el LB con tu contenedor)
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

# 7. Listener del Load Balancer (escucha en puerto 80)
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
# SERVICE DE ECS (el que ejecuta el contenedor)
# ==========================================

# 8. Service de ECS Fargate
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
# ROLES IAM (necesarios para ECS Fargate)
# ==========================================

# 9. Rol de ejecución para ECS (permite descargar imágenes de ECR)
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

  tags = {
    Name = "ecs-execution-role"
  }
}

# 10. Política para el rol de ejecución
resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 11. Rol de tarea para ECS (permisos para la app)
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

  tags = {
    Name = "ecs-task-role"
  }
}

# ==========================================
# OUTPUTS (Direcciones e Información Útil)
# ==========================================

# Muestra la URL del registro ECR donde el pipeline debe subir la imagen Docker
output "ecr_repository_url" {
  description = "URL del registro ECR en AWS"
  value       = aws_ecr_repository.app_repo.repository_url
}

# Muestra el nombre del cluster ECS creado
output "ecs_cluster_name" {
  description = "Nombre del cluster ECS"
  value       = aws_ecs_cluster.main.name
}

# Muestra la URL pública del Load Balancer
output "load_balancer_dns" {
  description = "DNS del Load Balancer para acceder a la aplicación"
  value       = aws_lb.app_lb.dns_name
}

# Muestra la URL completa con HTTP
output "app_url" {
  description = "URL pública completa para probar la aplicación"
  value       = "http://${aws_lb.app_lb.dns_name}"
}