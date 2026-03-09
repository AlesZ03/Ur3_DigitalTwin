import os
import json
import logging
import urllib.request
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
from botocore.session import get_session
import boto3
import math
# Logger beállítása
logger = logging.getLogger()
logger.setLevel(logging.INFO)
iot_data_client = boto3.client(
    'iot-data', 
    endpoint_url=f"https://{os.environ['IOT_ENDPOINT']}" 
)
# Környezeti változóból olvassuk az AppSync API URL-t
APPSYNC_API_URL = os.environ.get('APPSYNC_API_URL')
if not APPSYNC_API_URL:
    logger.error("FATAL: Missing required environment variable APPSYNC_API_URL.")
    raise ValueError("Missing APPSYNC_API_URL environment variable.")

REGION = APPSYNC_API_URL.split('.')[2]

# GraphQL Mutation
MUTATION = """
mutation PublishShadowUpdate($state: ShadowStateInput!, $version: Int, $timestamp: AWSTimestamp) {
  publishShadowUpdate(state: $state, version: $version, timestamp: $timestamp) {
    version
    state {
      reported {
        joint_positions
        timestamp
      }
    }
  }
}
"""
def apply_correction(joint_positions):
    """
    Elvégzi a 3D modellhez szükséges korrekciót a nyers csuklópozíciókon.
    """
    if not isinstance(joint_positions, list) or len(joint_positions) != 6:
        return joint_positions # Hiba esetén visszatér a nyers adattal

    # A JSX-ben lévő logika átültetve Pythonba
    corrected_positions = [
        joint_positions[0],                      # Joint 0: Váll forgatás (pan)
        joint_positions[1]+(math.pi/2),      # Joint 1: Váll emelés (lift)
        joint_positions[2],                      # Joint 2: Könyök
        joint_positions[3] +(math.pi/2),                   # Joint 3: Csukló 1
        joint_positions[4]*-1,                      # Joint 4: Csukló 2
        joint_positions[5]                       # Joint 5: Csukló 3
    ]
    return corrected_positions

def sign_and_make_request(query, variables):
    """Aláírja a GraphQL kérést SigV4-gyel és elküldi a beépített urllib használatával."""
    session = get_session()
    credentials = session.get_credentials().get_frozen_credentials()
    
    payload = json.dumps({"query": query, "variables": variables}).encode('utf-8')
    
    request = AWSRequest(
        method="POST",
        url=APPSYNC_API_URL,
        data=payload,
        headers={'Content-Type': 'application/json'}
    )
    
    # Aláírás generálása és hozzáadása a headerekhez
    SigV4Auth(credentials, "appsync", REGION).add_auth(request)
    prepared_request = request.prepare()
    
    # HTTP kérés felépítése a beépített urllib.request segítségével
    req = urllib.request.Request(
        prepared_request.url,
        data=prepared_request.body,
        headers=prepared_request.headers,
        method=prepared_request.method
    )
    
    try:
        with urllib.request.urlopen(req) as response:
            response_body = response.read().decode('utf-8')
            logger.info(f"AppSync response status code: {response.status}")
            logger.info(f"AppSync response: {response_body}")
            return json.loads(response_body)
    except urllib.error.HTTPError as e:
        error_body = e.read().decode('utf-8')
        logger.error(f"HTTP Error calling AppSync: {e.code} - {error_body}")
        raise Exception(f"HTTPError {e.code}: {error_body}")
    except Exception as e:
        logger.error(f"Unexpected error calling AppSync: {str(e)}")
        raise e

def lambda_handler(event, context):
    if "info" in event and event["info"]["fieldName"] == "getLatestShadowUpdate":
        logger.info("AppSync Query detected: Fetching shadow from IoT Core")
        try:
            response = iot_data_client.get_thing_shadow(thingName="UR3-Robot-001")
            shadow_payload = json.loads(response['payload'].read().decode('utf-8'))
            
            # Korrekció alkalmazása a shadow adatokra is
            state = shadow_payload.get("state", {})
            reported = state.get('reported', {})
            if 'joint_positions' in reported:
                reported['joint_positions'] = apply_correction(reported['joint_positions'])
                state['reported'] = reported
            
            return {
                "state": state,
                "version": shadow_payload.get("version"),
                "timestamp": shadow_payload.get("timestamp")
            }
        except Exception as e:
            logger.error(f"Error fetching shadow: {str(e)}")
            raise e

    logger.info(f"Event received from IoT Rule: {json.dumps(event)}")
    state = event.get('state', {})
    reported = state.get('reported', {})
    if 'joint_positions' in reported:
        reported['joint_positions'] = apply_correction(reported['joint_positions'])
        state['reported'] = reported
        logger.info(f"Corrected joint positions: {reported['joint_positions']}")

    variables = {
        "state": state,  
        "timestamp": event.get('timestamp')
    }
    try:
        logger.info(f"Calling AppSync mutation with variables: {json.dumps(variables)}")
        response = sign_and_make_request(MUTATION, variables)
        return {'statusCode': 200, 'body': json.dumps(response)}
    except Exception as e:
        logger.error(f"Error in lambda execution: {str(e)}")
        return {'statusCode': 500, 'body': f"Error calling AppSync: {str(e)}"}