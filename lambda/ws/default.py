import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """
    Default handler for unexpected WebSocket messages.
    Logs the event and returns a success response.
    """
    logger.info(f"Default route triggered with event: {json.dumps(event)}")
    return {
        'statusCode': 200,
        'body': 'Message received.'
    }