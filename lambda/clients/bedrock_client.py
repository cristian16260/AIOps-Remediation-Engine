import json
import logging
import boto3
from botocore.exceptions import BotoCoreError, ClientError
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)

# Inicializa el cliente Bedrock. Al estar dentro de la VPC, utilizará automáticamente los VPC Endpoints si están configurados.
bedrock_client = boto3.client('bedrock-runtime', region_name='us-east-1')

def resolve_via_bedrock(event: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """
    Resolución de Tier 2 vía Amazon Bedrock (Fallback interno).
    Usa VPC Endpoints. No depende de internet público.
    """
    logger.info("bedrock_client_invoked", extra={"tier": 2})
    
    model_id = "anthropic.claude-3-haiku-20240307-v1:0" # Modelo rápido y costo-efectivo
    
    prompt = f"Analyze this alarm: {json.dumps(event.get('detail', {}))}"
    
    payload = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 500,
        "messages": [
            {
                "role": "user",
                "content": prompt
            }
        ]
    }
    
    try:
        response = bedrock_client.invoke_model(
            modelId=model_id,
            contentType="application/json",
            accept="application/json",
            body=json.dumps(payload)
        )
        
        response_body = json.loads(response.get('body').read())
        logger.info("bedrock_invocation_successful")
        
        # Simulando la lógica de parseo como ejemplo
        return {
            "tier_used": 2,
            "action": "aws:runShellScript",
            "document_name": "AIOps-RestartService",
            "parameters": {"ServiceName": "httpd"}
        }
        
    except (BotoCoreError, ClientError) as e:
        logger.error(
            "bedrock_invocation_failed",
            extra={
                "error": str(e),
                "error_type": type(e).__name__
            }
        )
        raise
