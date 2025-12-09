import json
import boto3
from datetime import datetime, timedelta
import os

s3 = boto3.client('s3')
bucket_name = os.environ['S3_BUCKET_NAME']

def lambda_handler(event, context):
    """
    Lambda API a robot logok olvasásához S3-ból
    """
    
    try:
        # Query paraméterek
        query_params = event.get('queryStringParameters', {}) or {}
        limit = int(query_params.get('limit', 50))
        date_filter = query_params.get('date', datetime.utcnow().strftime('%Y/%m/%d'))
        
        print(f"📖 Reading logs from s3://{bucket_name}/robot-data/{date_filter}/")
        
        # S3 objektumok listázása
        prefix = f"robot-data/{date_filter}/"
        
        response = s3.list_objects_v2(
            Bucket=bucket_name,
            Prefix=prefix,
            MaxKeys=limit
        )
        
        logs = []
        
        # Objektumok olvasása
        for obj in response.get('Contents', [])[:limit]:
            key = obj['Key']
            
            try:
                # Fájl tartalmának olvasása
                file_obj = s3.get_object(Bucket=bucket_name, Key=key)
                content = file_obj['Body'].read().decode('utf-8')
                log_data = json.loads(content)
                
                # Hozzáadás a listához
                logs.append({
                    'key': key,
                    'timestamp': log_data.get('timestamp', ''),
                    'data': log_data.get('data', {}),
                    'message_id': log_data.get('message_id', ''),
                    'size': obj['Size'],
                    'last_modified': obj['LastModified'].isoformat()
                })
                
            except Exception as e:
                print(f"✗ Error reading {key}: {str(e)}")
                continue
        
        # Legfrissebb előre rendezés
        logs.sort(key=lambda x: x['timestamp'], reverse=True)
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            'body': json.dumps({
                'success': True,
                'count': len(logs),
                'logs': logs,
                'bucket': bucket_name,
                'date': date_filter
            })
        }
        
    except Exception as e:
        print(f"✗ Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'success': False,
                'error': str(e)
            })
        }