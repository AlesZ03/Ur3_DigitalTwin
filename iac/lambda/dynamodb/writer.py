import boto3
import base64
import json
import os
import math  # <-- Ezt hozzáadtuk a Pi számolásához
from decimal import Decimal

# Csatlakozás a DynamoDB-hez
dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('TABLE_NAME', 'Ur3_DigitalTwin-telemetry') 
table = dynamodb.Table(table_name)

def apply_correction(joint_positions):
    """
    Elvégzi a 3D modellhez szükséges korrekciót a nyers csuklópozíciókon.
    """
    if not isinstance(joint_positions, list) or len(joint_positions) != 6:
        return joint_positions

    corrected_positions = [
        float(joint_positions[0]),                      
        float(joint_positions[1]) + (math.pi/2),      
        float(joint_positions[2]),                      
        float(joint_positions[3]) + (math.pi/2),                   
        float(joint_positions[4]) * -1,                      
        float(joint_positions[5])                       
    ]
    return corrected_positions

def handler(event, context):
    output_records = []

    # A DynamoDB batch_writer-t használjuk a hatékony, csoportos íráshoz 
    with table.batch_writer() as batch:
        for record in event['records']:
            try:
                # 1. Firehose adat dekódolása (Base64)
                payload = base64.b64decode(record['data']).decode('utf-8')
                parsed_data = json.loads(payload)

               
                raw_joints = parsed_data['data']['joint_positions']
                corrected_joints = apply_correction(raw_joints)

                # 2. DynamoDB rekord összeállítása JSON formátum alapján
                item = {
                    'robot_id': 'ur3',
                    'timestamp': Decimal(str(parsed_data['data']['timestamp'])), 
                    'message_id': parsed_data.get('message_id', 'unknown'),
                    'received_at': parsed_data.get('received_at', ''),
                    
                 
                    'joint_positions': [Decimal(str(pos)) for pos in raw_joints],
                    
                   
                    'corrected_joints': [Decimal(str(pos)) for pos in corrected_joints]
                }
                
                # 3. Írás a batch-be (a háttérben automatikusan elküldi, ha megtelik)
                batch.put_item(Item=item)

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