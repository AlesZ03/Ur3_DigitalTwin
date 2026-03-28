import json
import boto3
import os
import logging
import re
from datetime import datetime, timezone
from boto3.dynamodb.conditions import Key
from decimal import Decimal

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
s3_client = boto3.client('s3')

TABLE_NAME = os.environ.get('TABLE_NAME')
BUCKET_NAME = os.environ.get('BUCKET_NAME')
table = dynamodb.Table(TABLE_NAME) if TABLE_NAME else None

CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'
}

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj) if obj % 1 else int(obj)
        if isinstance(obj, datetime):
            return obj.isoformat()
        return super(DecimalEncoder, self).default(obj)

def create_response(status_code, body):
    return {
        'statusCode': status_code,
        'headers': CORS_HEADERS,
        'body': json.dumps(body, cls=DecimalEncoder) 
    }

def lambda_handler(event, context):
    logger.info(f"Esemény fogadva: {json.dumps(event)}")

    http_method = event.get('httpMethod', 'GET').upper()
    if http_method == 'OPTIONS':
        return create_response(200, {"message": "CORS preflight check sikeres"})

    if not TABLE_NAME:
        logger.error("KRITIKUS HIBA: A TABLE_NAME környezeti változó nincs beállítva.")
        return create_response(500, {'error': 'Szerver konfigurációs hiba.'})

    try:
        params = event.get('queryStringParameters') or {}
        limit_str = params.get('limit')
        order = params.get('order', 'desc').lower()
        date_str = params.get('date') 
        start_time_str = params.get('startTime')
        end_time_str = params.get('endTime')
        
        is_desc = (order == 'desc')
        limit = int(limit_str) if limit_str else None
        
        key_condition = Key('robot_id').eq('ur3')

        start_ts = 0
        end_ts = 0
        if date_str and start_time_str and end_time_str:
            try:
                start_dt_str = f"{date_str} {start_time_str}"
                end_dt_str = f"{date_str} {end_time_str}"
                
                dt_start = datetime.strptime(start_dt_str, '%Y/%m/%d %H:%M').replace(tzinfo=timezone.utc)
                dt_end = datetime.strptime(end_dt_str, '%Y/%m/%d %H:%M').replace(tzinfo=timezone.utc)
                
                start_ts = dt_start.timestamp()
                end_ts = dt_end.timestamp() + 59.999 
                
                key_condition = key_condition & Key('timestamp').between(Decimal(str(start_ts)), Decimal(str(end_ts)))
            except ValueError:
                return create_response(400, {'error': "Érvénytelen dátum/idő formátum!"})

        # 1. Lekérdezés a DynamoDB-ből
        raw_items = []
        query_kwargs = {
            'KeyConditionExpression': key_condition,
            'ScanIndexForward': not is_desc, 
        }
        
        if limit:
            query_kwargs['Limit'] = limit

        while True:
            response = table.query(**query_kwargs)
            raw_items.extend(response.get('Items', []))

            if limit and len(raw_items) >= limit:
                raw_items = raw_items[:limit]
                break
                
            if len(raw_items) >= 10000:
                break

            if 'LastEvaluatedKey' in response:
                query_kwargs['ExclusiveStartKey'] = response['LastEvaluatedKey']
            else:
                break

        # 2. A NYOMOZÓ ÉS A "TELJES NAPOS" REHYDRATION LOGIKA
        needs_rehydration = False
        info_message = None

        if date_str and start_time_str and BUCKET_NAME:
            oldest_db_ts = float(raw_items[-1].get('timestamp', 0)) if (is_desc and raw_items) else (float(raw_items[0].get('timestamp', 0)) if raw_items else None)
            TOLERANCE_SECONDS = 300 
            
            if not raw_items or oldest_db_ts > (start_ts + TOLERANCE_SECONDS):
                logger.info("Hiányos adatokat sejtünk a DynamoDB-ben. Irány az S3!")
                
                try:
                    s3_prefix = f"data/{date_str.replace('-', '/')}/"
                    s3_first_check = s3_client.list_objects_v2(Bucket=BUCKET_NAME, Prefix=s3_prefix, MaxKeys=1)
                    
                    if 'Contents' in s3_first_check and len(s3_first_check['Contents']) > 0:
                        first_file_key = s3_first_check['Contents'][0]['Key']
                        file_obj = s3_client.get_object(Bucket=BUCKET_NAME, Key=first_file_key)
                        file_content = file_obj['Body'].read().decode('utf-8')
                        
                        first_json_match = re.search(r'\{.*?\}(?=\s*\{|\s*$)', file_content)
                        
                        if first_json_match:
                            first_item = json.loads(first_json_match.group(0), parse_float=Decimal)
                            
                            if 'data' in first_item and 'timestamp' in first_item['data']:
                                oldest_s3_ts = float(first_item['data']['timestamp'])
                            else:
                                oldest_s3_ts = float(first_item.get('timestamp', 0)) 
                            
                            if not raw_items:
                                if oldest_s3_ts <= end_ts:
                                    needs_rehydration = True 
                                else:
                                    info_message = "A robot aznap be volt kapcsolva, de a kért időablakban nem mozgott/küldött adatot."
                            else:
                                if oldest_s3_ts < (oldest_db_ts - TOLERANCE_SECONDS):
                                    needs_rehydration = True 
                                else:
                                    info_message = "Minden elérhető adat betöltve. A robot korábban ki volt kapcsolva."
                        else:
                            logger.error("Nem találtunk érvényes JSON objektumot az első S3 fájlban.")
                    else:
                        info_message = "Ezen a napon a robot egyáltalán nem volt bekapcsolva (S3 vödör üres)."
                        
                except Exception as e:
                    logger.error(f"Hiba az S3 ellenőrzés során: {e}")

        # 3. TELJES NAP LETÖLTÉSE ÉS CACHE-ELÉSE
       
        if needs_rehydration:
            logger.info(f"TELJES NAP betöltése indul az S3-ból a gyorsítótárba: {date_str}...")
            try:
                rehydrated_items = []
                s3_prefix = f"data/{date_str.replace('-', '/')}/"
                
                paginator = s3_client.get_paginator('list_objects_v2')
                pages = paginator.paginate(Bucket=BUCKET_NAME, Prefix=s3_prefix)
                
                for page in pages:
                    if 'Contents' in page:
                        for obj in page['Contents']:
                            file_key = obj['Key']
                            file_obj = s3_client.get_object(Bucket=BUCKET_NAME, Key=file_key)
                            file_content = file_obj['Body'].read().decode('utf-8')
                            
                            json_objects = re.findall(r'\{.*?\}(?=\s*\{|\s*$)', file_content)
                            for json_str in json_objects:
                                try:
                                    item_data = json.loads(json_str, parse_float=Decimal)
                                    item_data['robot_id'] = 'ur3' 
                                    
                                    if 'data' in item_data and 'timestamp' in item_data['data']:
                                        item_data['timestamp'] = Decimal(str(item_data['data']['timestamp']))
                                    else:
                                        item_data['timestamp'] = Decimal(str(item_data.get('timestamp', 0)))

                                  
                                    raw_joints = item_data.get('data', {}).get('joint_positions', item_data.get('joint_positions', []))
                                    

                                    import math
                                    if 'corrected_joints' not in item_data and isinstance(raw_joints, list) and len(raw_joints) == 6:
                                        item_data['corrected_joints'] = [
                                            Decimal(str(raw_joints[0])),
                                            Decimal(str(float(raw_joints[1]) + (math.pi/2))),
                                            Decimal(str(raw_joints[2])),
                                            Decimal(str(float(raw_joints[3]) + (math.pi/2))),
                                            Decimal(str(float(raw_joints[4]) * -1)),
                                            Decimal(str(raw_joints[5]))
                                        ]

                                    rehydrated_items.append(item_data)
                                except Exception as e:
                                    logger.error(f"Hiba JSON olvasáskor: {e}. Tartalom: {json_str[:50]}...")
                
                if rehydrated_items:
                    logger.info(f"{len(rehydrated_items)} rekord letöltve a teljes naphoz. Írás a DB-be...")
                    new_expire_at = int(datetime.now().timestamp()) + 86400 # 24 óra TTL
                    
                    with table.batch_writer() as batch:
                        for item in rehydrated_items:
                            item['expire_at'] = new_expire_at 
                            batch.put_item(Item=item)
                    
                    logger.info("A teljes nap sikeresen gyorsítótárazva a DynamoDB-ben!")
                    
                    raw_items = [
                        item for item in rehydrated_items 
                        if start_ts <= float(item.get('timestamp', 0)) <= end_ts
                    ]
                    raw_items.sort(key=lambda x: float(x.get('timestamp', 0)), reverse=is_desc)
                    info_message = "Hiányzó adatok észlelve, a teljes nap visszatöltésre került a gyorsítótárba!"
            except Exception as e:
                logger.error(f"Hiba a teljes napos Rehydration során: {e}")

        # 4. Válasz formázása a Frontendnek
        formatted_items = []
        for item in raw_items:
            ts = float(item.get('timestamp', 0))
            approx_size_bytes = len(json.dumps(item, cls=DecimalEncoder))
            dt_obj = datetime.fromtimestamp(ts, tz=timezone.utc)
            
         
            raw_joints = item.get('joint_positions', [])
            corrected_joints = item.get('corrected_joints', [])

            formatted_items.append({
                "key": f"dynamodb-record/{item.get('message_id', 'unknown')}", 
                "size": approx_size_bytes,                                                     
                "message_id": item.get('message_id', ''),
                "timestamp": dt_obj.strftime('%Y-%m-%d_%H-%M-%S'), 
                "received_at": item.get('received_at', dt_obj.isoformat()),
                "data": {                                                     
                    "joint_positions": raw_joints,               
                    "corrected_joints": corrected_joints,
                    "timestamp": ts
                }
            })

        response_body = {
            "logs": formatted_items,
            "info_message": info_message
        }

        return create_response(200, response_body)

    except Exception as e:
        logger.error(f"Váratlan hiba történt: {e}", exc_info=True)
        return create_response(500, {'error': 'Belső szerverhiba történt.'})