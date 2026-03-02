import json
import boto3
import os
import logging
import math


# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Get environment variables set by Terraform
WEBSOCKET_API_ENDPOINT = os.environ.get('WEBSOCKET_API_ENDPOINT')
DYNAMODB_TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME')

# Check for missing environment variables at cold start
if not WEBSOCKET_API_ENDPOINT or not DYNAMODB_TABLE_NAME:
    logger.error("FATAL: Missing required environment variables WEBSOCKET_API_ENDPOINT or DYNAMODB_TABLE_NAME.")
    # This will cause subsequent invocations to fail until the environment is fixed.
    raise ValueError("Missing required environment variables.")

# Initialize AWS clients outside the handler for better performance (reuse)
dynamodb = boto3.resource('dynamodb')
connections_table = dynamodb.Table(DYNAMODB_TABLE_NAME)
# The endpoint_url is crucial for the ApiGatewayManagementApi client to know where to send messages
apigw_management_client = boto3.client('apigatewaymanagementapi', endpoint_url=WEBSOCKET_API_ENDPOINT)

def apply_correction(joint_positions):
    """
    Elvégzi a 3D modellhez szükséges korrekciót a nyers csuklópozíciókon.
    """
    if not isinstance(joint_positions, list) or len(joint_positions) != 6:
        return joint_positions # Hiba esetén visszatér a nyers adattal

    # A JSX-ben lévő logika átültetve Pythonba
    corrected_positions = [
        joint_positions[0]+ (math.pi / 2),                      # Joint 0: Váll forgatás (pan)
        joint_positions[1] + (math.pi / 2),      # Joint 1: Váll emelés (lift)
        joint_positions[2],                      # Joint 2: Könyök
        joint_positions[3] + (math.pi / 2),                     # Joint 3: Csukló 1
        joint_positions[4] - (math.pi / 2),                      # Joint 4: Csukló 2
        joint_positions[5]                       # Joint 5: Csukló 3
    ]
    return corrected_positions


def lambda_handler(event, context):
    """
    This function is triggered by an IoT Core rule. It receives telemetry data,
    retrieves all active WebSocket connection IDs from DynamoDB, and pushes
    the telemetry data to each connected client.
    """
    logger.info(f"Received event: {json.dumps(event)}")

    # 1. Extract the joint positions from the incoming event.
    # The structure of 'event' depends on your IoT rule's SQL query.
    # We assume the data is directly in the event body.
    joint_positions = event.get('joint_positions') # Corrected key from 'joints' to 'joint_positions'
    
    if not joint_positions or not isinstance(joint_positions, list):
        logger.warning(f"Event does not contain a valid 'joint_positions' list. Skipping broadcast. Event: {event}")
        # Also handle the TwinMaker keep-alive pings gracefully
        if event.get('request') and event['request'].get('properties'):
            logger.info("Detected TwinMaker property update request, not telemetry. Skipping.")
            # TwinMaker requires a specific response format for property updates
            return {
                "response": {
                    "properties": []
                }
            }
        return {'statusCode': 200, 'body': 'Not a telemetry event.'}

    # 2. Get all active connection IDs from DynamoDB.
    try:
        response = connections_table.scan(ProjectionExpression='connectionId')
        connection_ids = [item['connectionId'] for item in response.get('Items', [])]
        logger.info(f"Found {len(connection_ids)} active connections.")
    except Exception as e:
        logger.error(f"Failed to scan DynamoDB table '{DYNAMODB_TABLE_NAME}': {e}")
        return {'statusCode': 500, 'body': 'Failed to retrieve connections.'}

    if not connection_ids:
        logger.info("No active WebSocket connections. Nothing to do.")
        return {'statusCode': 200, 'body': 'No active connections.'}

    # 3. Prepare the payload to be sent to the frontend.
    # The frontend expects a JSON object with a 'joint_positions' key.
    corrected_positions = apply_correction(joint_positions)
    payload = json.dumps({
        'joint_positions': corrected_positions
    })
    
    # 4. Broadcast the payload to all connected clients.
    stale_connections = []
    for connection_id in connection_ids:
        try:
            apigw_management_client.post_to_connection(ConnectionId=connection_id, Data=payload)
        except apigw_management_client.exceptions.GoneException:
            logger.warning(f"Connection {connection_id} is stale. Marking for deletion.")
            stale_connections.append(connection_id)
        except Exception as e:
            logger.error(f"Failed to post to connection {connection_id}: {e}")

    # 5. Clean up any stale connections found.
    for connection_id in stale_connections:
        connections_table.delete_item(Key={'connectionId': connection_id})

    logger.info("Successfully broadcasted data to active connections.")
    return {'statusCode': 200, 'body': 'Data broadcasted successfully.'}