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

# El proveedor de AWS detecta automáticamente las variables de entorno:
# - AWS_ACCESS_KEY_ID
# - AWS_SECRET_ACCESS_KEY
# - AWS_REGION (o AWS_DEFAULT_REGION)
provider "aws" {
  # No se declaran credenciales aqui por seguridad.
  # Terraform las lee de la terminal automaticamente.
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

  container_definitions = jsonencode([
    {
      name      = "bash-app"
      image     = "${aws_ecr_repository.app_repo.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
        }
      ]
    }
  ])
}

# 4. Grupo de Seguridad (Security Group) para permitir tráfico al puerto 8080
resource "aws_security_group" "ecs_sg" {
  name        = "bash-app-ecs-sg"
  description = "Permitir trafico de entrada al puerto 8080"

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