import json
import boto3
import os
import logging
from datetime import datetime, timezone
import uuid

logging.basicConfig(level=logging.INFO)
sqs = boto3.client('sqs')
COMMAND_QUEUE_URL = os.getenv('COMMAND_QUEUE_URL')
if not COMMAND_QUEUE_URL:
    # Fail fast during Lambda init so misconfiguration is obvious
    raise RuntimeError('Missing required environment variable: COMMAND_QUEUE_URL')

def lambda_handler(event, context):
    """
    Lambda API parancsok küldéséhez a robot felé
    POST /command
    """
    
    try:
        # CORS preflight
        if event.get('httpMethod') == 'OPTIONS':
            return {
                'statusCode': 204,
                'headers': {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
                    'Access-Control-Allow-Headers': 'Content-Type'
                },
                'body': ''
            }

        # Parse request body
        if 'body' not in event:
            return error_response(400, 'Missing request body')
        
        body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
        
        # Validate command
        if 'command' not in body:
            return error_response(400, 'Missing command field')
        
        command = body['command']

        if not isinstance(command, dict):
            return error_response(400, 'command must be an object')
        
        # Parancs üzenet összeállítása
        message = {
            'command': command,
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'messageId': str(uuid.uuid4()),
            'source': 'dashboard'
        }
        
        # Opcionális metaadatok
        if 'metadata' in body:
            message['metadata'] = body['metadata']
        
        logging.info("Sending command to robot: %s", json.dumps(command))
        
        # SQS-be küldés
        response = sqs.send_message(
            QueueUrl=COMMAND_QUEUE_URL,
            MessageBody=json.dumps(message),
            MessageAttributes={
                'CommandType': {
                    'StringValue': command.get('action', 'unknown'),
                    'DataType': 'String'
                },
                'Priority': {
                    'StringValue': str(command.get('priority', 'normal')),
                    'DataType': 'String'
                }
            }
        )
        
        logging.info("Command sent successfully. MessageId: %s", response.get('MessageId'))
        
        return success_response({
            'success': True,
            'message': 'Command sent to robot',
            'messageId': response['MessageId'],
            'queueMessageId': response['MessageId'],
            'command': command,
            'timestamp': message['timestamp']
        })
        
    except json.JSONDecodeError as e:
        return error_response(400, f'Invalid JSON: {str(e)}')

    except Exception as e:
        logging.exception('Error in lambda_handler')
        return error_response(500, f'Internal error: {str(e)}')


def lambda_handler_get_status(event, context):
    """
    GET /command/status - Queue státusz lekérése
    """
    try:
        # Queue attribútumok lekérése
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
        
    except Exception as e:
        logging.exception('Error getting queue status')
        return error_response(500, f'Error: {str(e)}')


def success_response(data, status_code=200):
    """Success response helper"""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type'
        },
        'body': json.dumps(data)
    }


def error_response(status_code, message):
    """Error response helper"""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'success': False,
            'error': message
        })
    }