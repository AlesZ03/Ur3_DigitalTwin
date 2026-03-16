import json
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

IOT_ENDPOINT = os.environ.get('IOT_ENDPOINT')
if not IOT_ENDPOINT:
    logger.error("Hiba: IOT_ENDPOINT környezeti változó hiányzik!")

iot_client = boto3.client('iot-data', endpoint_url=f"https://{IOT_ENDPOINT}")

IOT_TOPIC = os.environ.get('IOT_TOPIC', 'ur3/commands')

def lambda_handler(event, context):
    logger.info(f"SQS Event érkezett: {json.dumps(event)}")
    
    for record in event.get('Records', []):
        try:
            payload_str = record['body']
            message_dict = json.loads(payload_str)
            
            logger.info(f"Üzenet feldolgozása és küldése az IoT Core-nak: {payload_str}")
            
            response = iot_client.publish(
                topic=IOT_TOPIC,
                qos=1,
                payload=json.dumps(message_dict)
            )
            
            logger.info(f"Sikeres publikálás a {IOT_TOPIC} topikba.")
            
        except Exception as e:
            logger.error(f"Hiba az üzenet feldolgozása során (ID: {record.get('messageId')}): {str(e)}")
            raise e
            
    return {
        'statusCode': 200,
        'body': json.dumps('SQS üzenetek sikeresen továbbítva az IoT Core felé.')
    }