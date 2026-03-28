import json
import boto3
import os
import logging
from datetime import datetime, timezone
from boto3.dynamodb.conditions import Key
from decimal import Decimal

# Logging beállítása
logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
s3_client = boto3.client('s3')

TABLE_NAME = os.environ.get('TABLE_NAME')
BUCKET_NAME = os.environ.get('BUCKET_NAME')
table = dynamodb.Table(TABLE_NAME) if TABLE_NAME else None

# --- CORS Fejlécek ---
CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'
}

# --- Egyedi JSON Encoder a DynamoDB miatt ---
class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj) if obj % 1 else int(obj)
        if isinstance(obj, datetime):
            return obj.isoformat()
        return super(DecimalEncoder, self).default(obj)

def create_response(status_code, body):
    """Segédfüggvény a konzisztens API Gateway válaszokhoz."""
    return {
        'statusCode': status_code,
        'headers': CORS_HEADERS,
        'body': json.dumps(body, cls=DecimalEncoder) 
    }

def lambda_handler(event, context):
    logger.info(f"Esemény fogadva: {json.dumps(event)}")

    # --- CORS Preflight ---
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

        # Dátum és idő konvertálása
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
                logger.warning("Elértük a 10 000 elemes biztonsági korlátot a lekérdezésnél!")
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
            
            # Ha üres, vagy gyanúsan későn kezdődik az adatbázis tartalma
            if not raw_items or oldest_db_ts > (start_ts + TOLERANCE_SECONDS):
                logger.info("Hiányos adatokat sejtünk a DynamoDB-ben. Irány az S3!")
                
                try:
                    s3_prefix = date_str.replace('-', '/') + '/' 
                    
                    # Először csak a legelső fájlt kérjük le, hogy lássuk, volt-e egyáltalán adat aznap!
                    s3_first_check = s3_client.list_objects_v2(Bucket=BUCKET_NAME, Prefix=s3_prefix, MaxKeys=1)
                    
                    if 'Contents' in s3_first_check and len(s3_first_check['Contents']) > 0:
                        first_file_key = s3_first_check['Contents'][0]['Key']
                        file_obj = s3_client.get_object(Bucket=BUCKET_NAME, Key=first_file_key)
                        first_line = file_obj['Body'].read().decode('utf-8').strip().split('\n')[0]
                        oldest_s3_ts = float(json.loads(first_line).get('timestamp', 0))
                        
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
                        info_message = "Ezen a napon a robot egyáltalán nem volt bekapcsolva (S3 vödör üres)."
                        
                except Exception as e:
                    logger.error(f"Hiba az S3 ellenőrzés során: {e}")

        # 3. TELJES NAP LETÖLTÉSE ÉS CACHE-ELÉSE
        if needs_rehydration:
            logger.info(f"TELJES NAP betöltése indul az S3-ból a gyorsítótárba: {date_str}...")
            try:
                rehydrated_items = []
                s3_prefix = date_str.replace('-', '/') + '/' 
                
                # Paginator kell, mert egy nap alatt több mint 1000 fájl is lehet az S3-ban!
                paginator = s3_client.get_paginator('list_objects_v2')
                pages = paginator.paginate(Bucket=BUCKET_NAME, Prefix=s3_prefix)
                
                for page in pages:
                    if 'Contents' in page:
                        for obj in page['Contents']:
                            file_key = obj['Key']
                            file_obj = s3_client.get_object(Bucket=BUCKET_NAME, Key=file_key)
                            file_content = file_obj['Body'].read().decode('utf-8')
                            
                            for line in file_content.strip().split('\n'):
                                if line:
                                    rehydrated_items.append(json.loads(line))
                
                if rehydrated_items:
                    logger.info(f"{len(rehydrated_items)} rekord letöltve a teljes naphoz. Írás a DB-be...")
                    new_expire_at = int(datetime.now().timestamp()) + 86400 # 24 óra TTL
                    
                    with table.batch_writer() as batch:
                        for item in rehydrated_items:
                            item['expire_at'] = new_expire_at 
                            batch.put_item(Item=item)
                    
                    logger.info("A teljes nap sikeresen gyorsítótárazva a DynamoDB-ben!")
                    
                    # SZŰRÉS: Mivel az egész napot letöltöttük, most kiválogatjuk belőle azt,
                    # amit a frontend éppen most konkrétan kért!
                    raw_items = [
                        item for item in rehydrated_items 
                        if start_ts <= float(item.get('timestamp', 0)) <= end_ts
                    ]
                    # Rendezzük a megfelelő irányba
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
            formatted_items.append({
                "key": f"dynamodb-record/{item.get('message_id', 'unknown')}", 
                "size": approx_size_bytes,                                                     
                "message_id": item.get('message_id', ''),
                "timestamp": dt_obj.strftime('%Y-%m-%d_%H-%M-%S'), 
                "received_at": dt_obj.isoformat(),
                "data": {                                                     
                    "joint_positions": item.get('joint_positions', []),
                    "timestamp": item.get('timestamp', 0)
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