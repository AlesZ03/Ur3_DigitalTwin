import boto3
import base64
import json
import os
from decimal import Decimal

# Csatlakozás a DynamoDB-hez
dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('TABLE_NAME', 'Ur3_DigitalTwin-telemetry') 
table = dynamodb.Table(table_name)

def handler(event, context):
    output_records = []

    # A DynamoDB batch_writer-t használjuk a hatékony, csoportos íráshoz 
    with table.batch_writer() as batch:
        for record in event['records']:
            try:
                # 1. Firehose adat dekódolása (Base64)
                payload = base64.b64decode(record['data']).decode('utf-8')
                parsed_data = json.loads(payload)

                # 2. DynamoDB rekord összeállítása  JSON formátum alapján
                
                item = {
                    'robot_id': 'ur3',
                    'timestamp': Decimal(str(parsed_data['data']['timestamp'])), 
                    'message_id': parsed_data.get('message_id', 'unknown'),
                    'received_at': parsed_data.get('received_at', ''),
                    'joint_positions': [Decimal(str(pos)) for pos in parsed_data['data']['joint_positions']]
                }
                
                # 3. Írás a batch-be (a háttérben automatikusan elküldi, ha megtelik)
                batch.put_item(Item=item)

                # 4. Firehose-nak jelezzük a sikert, hogy mehessen az adat S3-ba is
                output_records.append({
                    'recordId': record['recordId'],
                    'result': 'Ok',
                    'data': record['data'] 
                })
            
            except Exception as e:
                print(f"Hiba a rekord feldolgozásakor: {e}")
                output_records.append({
                    'recordId': record['recordId'],
                    'result': 'ProcessingFailed',
                    'data': record['data']
                })

    return {'records': output_records}