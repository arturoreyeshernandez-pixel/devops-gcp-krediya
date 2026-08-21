# Guía E2E: Despliegue DevOps en AWS con Docker, Terraform y GitHub Actions

---

### Paso 1: Código de la Aplicación y Dockerfile
Script en Bash escuchando en el puerto 8080 empaquetado en una imagen ultraligera basada en Alpine Linux (< 10 MB).

**app.sh**
#!/bin/sh
PORT=${PORT:-8080}
while true; do
  echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"message\": \"Hello World desde Bash en AWS!\", \"status\": \"OK\"}" | nc -l -p $PORT -q 1
done


**Dockerfile**
FROM alpine:latest
RUN apk add --no-cache netcat-openbsd
WORKDIR /app
COPY app.sh .
RUN chmod +x app.sh
EXPOSE 8080
CMD ["./app.sh"]

---

### Paso 2: Pruebas Locales del Contenedor
Comandos para validar que la imagen compila y responde localmente antes de tocar la nube:

docker build -t mi-app-bash .
docker run -d -p 8080:8080 --name app-test mi-app-bash
curl http://localhost:8080
docker stop app-test && docker rm app-test

---

### Paso 3: Infraestructura como Código (main.tf)
Definición declarativa de recursos en AWS (ECR, Cluster ECS Fargate, Task Definition y Security Group). Toma las credenciales automáticamente de las variables de entorno locales:

terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {} 

resource "aws_ecr_repository" "app_repo" {
  name = "bash-app-repo"
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

  container_definitions = jsonencode([{
    name      = "bash-app"
    image     = "${aws_ecr_repository.app_repo.repository_url}:latest"
    essential = true
    portMappings = [{ containerPort = 8080, hostPort = 8080 }]
  }])
}

resource "aws_security_group" "ecs_sg" {
  name = "bash-app-ecs-sg"
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

output "ecr_repository_url" {
  value = aws_ecr_repository.app_repo.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

---

### Paso 4: Credenciales de AWS IAM
Configuración de seguridad para ejecución local y automatizada en CI/CD:

1. En tu máquina local (para Terraform):
export AWS_ACCESS_KEY_ID="TU_ACCESS_KEY_DE_IAM"
export AWS_SECRET_ACCESS_KEY="TU_SECRET_KEY_DE_IAM"
export AWS_REGION="us-east-1"

2. En GitHub (para el Pipeline):
Ve a Settings > Secrets and variables > Actions.
Crea las variables: AWS_ACCESS_KEY_ID y AWS_SECRET_ACCESS_KEY.

---

### Paso 5: Pipeline CI/CD (.github/workflows/ci-cd.yml)
Workflow de GitHub Actions que se autentica en AWS, compila la app y valida Terraform:

name: CI/CD Pipeline - AWS Docker & Terraform
on:
  push:
    branches: [ "main" ]
jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configurar Credenciales AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1

      - name: Build & Test Docker Local
        run: |
          docker build -t mi-app-bash .
          docker run -d -p 8080:8080 --name test mi-app-bash
          sleep 2 && curl http://localhost:8080 && docker stop test

      - uses: hashicorp/setup-terraform@v3

      - name: Terraform Init & Validate
        run: |
          terraform init
          terraform validate

---

### Paso 6: Despliegue y URL Pública
Secuencia final para aprovisionar infraestructura y obtener el endpoint funcional:

1. Crear infraestructura en AWS con Terraform:
terraform init
terraform apply -auto-approve

2. Copiar la URL de ECR mostrada en la sección "Outputs:" al finalizar Terraform.

3. Subir cambios a GitHub para que el pipeline valide y autentique:
git add .
git commit -m "feat: deploy e2e pipeline"
git push origin main

4. Probar el servicio usando la IP o URL pública obtenida en el puerto 8080:
curl http://<URL_DEL_SERVICIO>:8080