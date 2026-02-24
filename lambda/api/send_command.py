import json
import boto3
import os
import logging
from datetime import datetime, timezone
import uuid

# --- Konfiguráció és kliensek ---
logger = logging.getLogger()
logger.setLevel(logging.INFO)

sqs = boto3.client('sqs')
COMMAND_QUEUE_URL = os.getenv('COMMAND_QUEUE_URL')

# A frontendről áthelyezett, központosított gyorsparancsok
QUICK_COMMANDS = [
    { 'label': 'Home Position', 'command': { 'action': 'move', 'joints': [0.0, -1.57, 1.57, -1.57, -1.57, 0.0] } },
    { 'label': 'Stop', 'command': { 'action': 'stop' } },
    { 'label': 'Test Position 1', 'command': { 'action': 'move', 'joints': [1.0, -1.8, 2.0, -1.7, -1.57, 0.0] } },
    { 'label': 'Test Position 2', 'command': { 'action': 'move', 'joints': [-1.0, -1.2, -2.0, -1.5, -1.57, 0.0] } }
]

CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'
}

def success_response(data, status_code=200):
    """Success response helper"""
    return {
        'statusCode': status_code,
        'headers': {**CORS_HEADERS, 'Content-Type': 'application/json'},
        'body': json.dumps(data)
    }

def error_response(status_code, message):
    """Error response helper"""
    return {
        'statusCode': status_code,
        'headers': {**CORS_HEADERS, 'Content-Type': 'application/json'},
        'body': json.dumps({
            'success': False,
            'error': message
        })
    }

def handle_get_quick_commands(event):
    """Handler for GET /command/quick"""
    logger.info("Handling GET /command/quick request.")
    return success_response(QUICK_COMMANDS)

def handle_post_command(event):
    """Handler for POST /command"""
    logger.info("Handling POST /command request.")
    body = json.loads(event['body']) if event.get('body') and isinstance(event['body'], str) else event.get('body', {})
    
    if 'command' not in body:
        return error_response(400, 'Missing "command" field in request body')
    
    command = body['command']
    if not isinstance(command, dict) or 'action' not in command:
        return error_response(400, '"command" must be an object with an "action" key')

    message = {
        'command': command,
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'messageId': str(uuid.uuid4()),
        'source': 'dashboard'
    }
    
    logger.info(f"Sending command to SQS: {json.dumps(message)}")
    
    response = sqs.send_message(
        QueueUrl=COMMAND_QUEUE_URL,
        MessageBody=json.dumps(message)
    )
    
    logger.info(f"Command sent successfully. SQS MessageId: {response.get('MessageId')}")
    
    return success_response({
        'success': True,
        'message': 'Command sent to robot',
        'sqsMessageId': response['MessageId'],
        'command': command
    })

def handle_get_status(event):
    """Handler for GET /command/status"""
    logger.info("Handling GET /command/status request.")
    response = sqs.get_queue_attributes(
        QueueUrl=COMMAND_QUEUE_URL,
        AttributeNames=[
            'ApproximateNumberOfMessages',
            'ApproximateNumberOfMessagesNotVisible',
            'ApproximateNumberOfMessagesDelayed'
        ]
    )
    
    attributes = response.get('Attributes', {})
    
    return success_response({
        'success': True,
        'queue': {
            'url': COMMAND_QUEUE_URL,
            'pendingMessages': int(attributes.get('ApproximateNumberOfMessages', 0)),
            'inFlightMessages': int(attributes.get('ApproximateNumberOfMessagesNotVisible', 0)),
            'delayedMessages': int(attributes.get('ApproximateNumberOfMessagesDelayed', 0))
        }
    })

def lambda_handler(event, context):
    """
    Single entry point for the /command API. Routes requests based on HTTP method and path.
    - GET /command/quick   -> Returns predefined quick commands.
    - POST /command        -> Sends a command to the SQS queue.
    - GET /command/status  -> Returns the status of the SQS queue.
    """
    if not COMMAND_QUEUE_URL:
        logger.critical("FATAL: COMMAND_QUEUE_URL environment variable is not set.")
        return error_response(500, 'Server configuration error.')

    http_method = event.get('httpMethod', 'GET').upper()
    path = event.get('path', '')

    # Handle CORS preflight requests globally
    if http_method == 'OPTIONS':
        logger.info("Handling OPTIONS preflight request.")
        return success_response({}, 204)

    try:
        # Simple router based on path suffix
        if http_method == 'GET' and path.endswith('/quick'):
            return handle_get_quick_commands(event)
        elif http_method == 'POST' and (path.endswith('/command') or path.endswith('/command/')):
            return handle_post_command(event)
        elif http_method == 'GET' and path.endswith('/status'):
            return handle_get_status(event)
        else:
            return error_response(404, f"Not Found: No route for {http_method} {path}")

    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in request body: {e}")
        return error_response(400, f'Invalid JSON: {str(e)}')
    except Exception as e:
        logger.exception('Unhandled error in lambda_handler')
        return error_response(500, f'Internal server error.')