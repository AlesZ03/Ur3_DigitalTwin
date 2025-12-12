import json
import boto3
import os
import logging
from datetime import datetime, timezone
import uuid

logging.basicConfig(level=logging.INFO)
s3_client = boto3.client('s3')
bucket_name = os.getenv('S3_BUCKET_NAME')
if not bucket_name:
    raise RuntimeError('Missing required environment variable: S3_BUCKET_NAME')

def handler(event, context):
    """
    Lambda handler ami feldolgozza az SQS üzeneteket és S3-ba menti őket
    """
    
    processed_count = 0
    failed_count = 0
    
    # Végigmegyünk az összes SQS üzeneten
    for record in event['Records']:
        try:
            # SQS üzenet tartalmának kinyerése
            message_body = record['body']
            message_id = record['messageId']
            
            # Timestamp és egyedi azonosító generálása
            timestamp = datetime.now(timezone.utc).strftime('%Y-%m-%d_%H-%M-%S')
            unique_id = str(uuid.uuid4())[:8]
            
            # S3 objektum kulcs generálása (mappa struktúra dátum alapján)
            date_path = datetime.utcnow().strftime('%Y/%m/%d')
            s3_key = f"robot-data/{date_path}/{timestamp}_{unique_id}.json"
            
            # Adat formázása
            data_to_store = {
                'message_id': message_id,
                'timestamp': timestamp,
                'received_at': datetime.now(timezone.utc).isoformat(),
                'data': json.loads(message_body) if is_json(message_body) else message_body
            }
            
            # Mentés S3-ba
            s3_client.put_object(
                Bucket=bucket_name,
                Key=s3_key,
                Body=json.dumps(data_to_store, indent=2),
                ContentType='application/json'
            )
            
            processed_count += 1
            logging.info('Saved to S3: %s', s3_key)
            
        except Exception as e:
            failed_count += 1
            logging.exception('Error processing record %s', record.get('messageId', 'N/A'))
            # A hiba nem stoppolja a többi üzenet feldolgozását
    
    # Válasz generálása
    response = {
        'statusCode': 200,
        'body': json.dumps({
            'processed': processed_count,
            'failed': failed_count,
            'bucket': bucket_name
        })
    }
    
    logging.info('Processing finished: %s processed, %s failed', processed_count, failed_count)
    
    return response

def is_json(text):
    """Ellenőrzi, hogy a string valid JSON-e"""
    try:
        json.loads(text)
        return True
    except:
        return False