# DevOps & Infrastructure Pipeline - AWS

Este repositorio contiene una solución ligera de infraestructura como código (IaC) y automatización CI/CD para el despliegue de una aplicación web en contenedores.

## 🛠️ Arquitectura y Tecnologías

* **Aplicación:** Script en Bash (`app.sh`) escuchando solicitudes HTTP en el puerto `8080` vía `netcat`.
* **Contenedor:** `Dockerfile` optimizado basado en **Alpine Linux** (< 10 MB).
* **IaC (Terraform):** Infraestructura declarativa en **AWS** (Amazon ECR, ECS Fargate, Task Definition y Security Groups).
* **CI/CD:** Pipeline en **GitHub Actions** (`.github/workflows/ci-cd.yml`) para validación de compilación, prueba de contenedor en ejecución y comprobación sintáctica de IaC.

---

## 🚀 Ejecución Local

### 1. Construir la imagen Docker
```bash
docker build -t mi-app-bash .