import json
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

DYNAMODB_TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(DYNAMODB_TABLE_NAME)

def handler(event, context):
    connection_id = event.get('requestContext', {}).get('connectionId')
    
    if not connection_id:
        logger.error("Missing connectionId in event")
        return {'statusCode': 400, 'body': 'Connection ID not found.'}

    if not DYNAMODB_TABLE_NAME:
        logger.error("DynamoDB table name environment variable not set.")
        return {'statusCode': 500, 'body': 'Internal server error.'}

    try:
        table.put_item(Item={'connectionId': connection_id})
        logger.info(f"Successfully registered connection: {connection_id}")
        return {'statusCode': 200, 'body': 'Connected.'}
    except Exception as e:
        logger.error(f"Failed to register connection {connection_id}: {e}")
        return {'statusCode': 500, 'body': 'Failed to connect.'}