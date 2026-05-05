# AIOps Remediation Engine (Dual-Tier Auto-Failover)

Un motor de remediación autónoma desplegado 100% con Terraform. Utiliza un patrón de **Chain of Responsibility** y **Circuit Breaker** para conmutar dinámicamente entre una API pública de LLM (Tier 1: ChatGPT/Anthropic) y un fallback interno (Tier 2: Amazon Bedrock) en caso de fallos, maximizando la resiliencia en la mitigación de alarmas de CloudWatch.

## Arquitectura

- **Infraestructura Base (Core):** Instancias EC2 monitoreadas por CloudWatch Agent.
- **Red Tier 1:** NAT Gateway para permitir salida a internet y llamadas a la API (ChatGPT).
- **Red Tier 2:** VPC Endpoints para ruteo 100% privado hacia Amazon Bedrock (Fallback).
- **Remediación:** AWS Lambda (Python) y AWS Systems Manager (SSM) para ejecutar comandos *Self-Healing*.

## Requisitos Previos

- **Terraform** (`>= 1.5.0`)
- **Python** (`>= 3.9`) para la instalación local de librerías.
- Credenciales de AWS configuradas en tu terminal (`aws configure`).
- Haber creado el archivo `terraform.tfvars` con tus IDs reales de VPC, Subredes y tu **API Key de OpenAI** (`llm_api_key`).

## Instrucciones de Despliegue Local

Al trabajar desde tu disco duro sin un pipeline automatizado, debes preparar las dependencias de la Lambda antes de que Terraform la comprima:

### 1. Construir las dependencias de la Lambda
Para que la Lambda tenga acceso a librerías externas como `requests` (usada en el Tier 1), ejecuta nuestro script de construcción desde la terminal de PowerShell:

```powershell
.\build.ps1
```
*Este comando instalará las dependencias descritas en `lambda/requirements.txt` directamente dentro de la carpeta `lambda/`.*

### 2. Inicializar Terraform
Descarga los proveedores necesarios y prepara el backend local:
```bash
terraform init
```

### 3. Verificar y Desplegar
Visualiza los cambios que se van a crear y aplícalos en tu cuenta de AWS:
```bash
terraform plan
terraform apply
```

## Control de FinOps (Costos)

El proyecto está diseñado de forma modular. En tu archivo `terraform.tfvars` puedes cambiar la variable `deployment_mode` para optimizar costos:
- `"api_only"`: Despliega solo el Core y el Tier 1. Útil para desarrollo.
- `"ha_failover"`: Despliega la red completa (Incluyendo los VPC Endpoints de Bedrock). Útil para simulaciones de alta disponibilidad o producción.
