import boto3
import base64
import json
import os
import time

write_client = boto3.client('timestream-write')

def handler(event, context):
    records_to_timestream = []
    output_records = []

    for record in event['records']:
        # 1. Firehose adat dekódolása (Base64)
        payload = base64.b64decode(record['data']).decode('utf-8')
        data = json.loads(payload)

        # 2. Timestream rekord összeállítása
        # Feltételezzük, hogy a robot küld 'robot_id'-t és értékeket
        timestream_record = {
            'Dimensions': [
                {'Name': 'robot_id', 'Value': data.get('robot_id', 'unknown')},
                {'Name': 'source_topic', 'Value': data.get('source_topic', 'ur3/logs')}
            ],
            'MeasureName': 'robot_metrics',
            'MeasureValueType': 'DOUBLE', # Vagy 'VARCHAR' a logokhoz
            'MeasureValue': str(data.get('load', 0)), # Példa érték
            'Time': str(int(time.time() * 1000)) # Milliszekundumban
        }
        
        records_to_timestream.append(timestream_record)
        
        # 3. Firehose-nak jelezzük, hogy sikeres volt a feldolgozás
        output_records.append({
            'recordId': record['recordId'],
            'result': 'Ok',
            'data': record['data']
        })

    # 4. CSOPORTOS ÍRÁS (Költséghatékony!)
    if records_to_timestream:
        try:
            write_client.write_records(
                DatabaseName=os.environ['DB_NAME'],
                TableName=os.environ['TABLE_NAME'],
                Records=records_to_timestream
            )
        except Exception as e:
            print(f"Hiba az íráskor: {e}")

    return {'records': output_records}