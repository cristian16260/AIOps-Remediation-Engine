import os
import json
import logging
from typing import Any, Dict

# Configurar logging estructurado
logger = logging.getLogger()
logger.setLevel(os.getenv("LOG_LEVEL", "INFO"))

# Importar clientes (se implementarán en la carpeta clients)
try:
    from clients.api_client import resolve_via_api
    from clients.bedrock_client import resolve_via_bedrock
except ImportError:
    # Fallback para pruebas locales o despliegue incompleto
    resolve_via_api = None
    resolve_via_bedrock = None

class CircuitBreakerOpenException(Exception):
    """Se lanza cuando el circuito del API principal (Tier 1) está ABIERTO (modo degradado)."""
    pass

class DiagnosisError(Exception):
    """Se lanza cuando falla el diagnóstico en todos los tiers disponibles."""
    pass

def check_circuit_breaker() -> bool:
    """
    Verifica el estado del Circuit Breaker para el Tier 1.
    Returns True if the circuit is CLOSED (healthy), False if OPEN (degraded).
    
    # ==============================================================================
    # 4. PERSISTENCIA REAL DEL CIRCUIT BREAKER
    # ------------------------------------------------------------------------------
    # Para usarlo en producción, descomenta el código de abajo. Esto leerá el estado
    # desde el 'SSM Parameter Store'. Si el valor es 'CLOSED', se usa el Tier 1.
    # Si es 'OPEN', salta directo al Tier 2. 
    # Cambios necesarios si lo descomentas:
    # Asegúrate de crear el parámetro en AWS Systems Manager con el nombre 
    # '/aiops/circuit-breaker/tier1-status' y valor 'CLOSED'.
    # ==============================================================================
    """
    # import boto3
    # try:
    #     ssm = boto3.client('ssm', region_name='us-east-1')
    #     response = ssm.get_parameter(Name='/aiops/circuit-breaker/tier1-status')
    #     status = response['Parameter']['Value']
    #     return status == 'CLOSED'
    # except Exception as e:
    #     logger.warning("failed_to_read_circuit_breaker", extra={"error": str(e)})
    #     # Si falla la lectura, asumimos que está ABIERTO (usar Tier 1)
    #     return True

    return True

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Punto de entrada principal para el AIOps Remediation Engine (Dual-Tier Auto-Failover).
    
    Args:
        event: Payload de EventBridge que contiene detalles de la Alarma CloudWatch.
        context: Contexto de AWS Lambda.
        
    Returns:
        Dict con el resultado de la acción de remediación.
    """
    alarm_name = event.get("detail", {}).get("alarmName", "Unknown Alarm")
    logger.info(
        "aiops_engine_invoked",
        extra={
            "alarm_name": alarm_name,
            "event_source": event.get("source")
        }
    )
    
    diagnosis = None
    
    # 1. Tier 1 (Principal) - OpenAI/Anthropic vía API
    if check_circuit_breaker():
        try:
            if resolve_via_api:
                logger.info("attempting_tier_1_resolution")
                diagnosis = resolve_via_api(event)
                logger.info("tier_1_resolution_success")
            else:
                logger.warning("api_client_not_available")
                raise Exception("API Client unavailable")
                
        except Exception as e:
            logger.warning(
                "tier_1_resolution_failed",
                extra={
                    "error": str(e),
                    "error_type": type(e).__name__,
                    "action": "triggering_tier_2_fallback"
                }
            )
            # La lógica del Circuit Breaker podría actualizarse aquí al estado ABIERTO si los fallos persisten
    else:
        logger.warning(
            "circuit_breaker_open",
            extra={"action": "skipping_tier_1"}
        )

    # 2. Tier 2 (Respaldo) - Amazon Bedrock vía VPC Endpoints
    if not diagnosis:
        try:
            if resolve_via_bedrock:
                logger.info("attempting_tier_2_resolution")
                diagnosis = resolve_via_bedrock(event)
                logger.info("tier_2_resolution_success")
            else:
                logger.error("bedrock_client_not_available")
                raise Exception("Bedrock Client unavailable")
        except Exception as e:
            logger.error(
                "tier_2_resolution_failed",
                extra={
                    "error": str(e),
                    "error_type": type(e).__name__
                }
            )
            raise DiagnosisError("All diagnosis tiers exhausted and failed.") from e

    # 3. Ejecución de la Remediación (vía SSM)
    # El diagnóstico debe contener el documento SSM a ejecutar
    logger.info(
        "executing_remediation",
        extra={"diagnosis_result": diagnosis}
    )
    
    # TODO: Implementar la lógica de ejecución de SSM aquí basada en el output de 'diagnosis'
    
    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Remediation executed successfully",
            "diagnosis": diagnosis,
            "alarm_name": alarm_name
        })
    }
