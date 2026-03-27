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

# DynamoDB kliens inicializálása
dynamodb = boto3.resource('dynamodb')
TABLE_NAME = os.environ.get('TABLE_NAME')
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
    """
    Kezeli a /logs végpontra érkező GET kéréseket.
    A legfrissebb adatokat kéri le a DynamoDB-ből.
    """
    logger.info(f"Esemény fogadva: {json.dumps(event)}")

    # --- CORS Preflight Kérés Kezelése ---
    http_method = event.get('httpMethod', 'GET').upper()
    if http_method == 'OPTIONS':
        return create_response(200, {"message": "CORS preflight check sikeres"})

    if not TABLE_NAME:
        logger.error("KRITIKUS HIBA: A TABLE_NAME környezeti változó nincs beállítva.")
        return create_response(500, {'error': 'Szerver konfigurációs hiba.'})

    try:
        # Query paraméterek kinyerése
        params = event.get('queryStringParameters') or {}
        limit = int(params.get('limit', 50))
        order = params.get('order', 'desc').lower()
        date_str = params.get('date') 

        is_desc = (order == 'desc')
        
        # 1. Alap lekérdezés feltétele: a robot_id alapján

        key_condition = Key('robot_id').eq('ur3')

        # 2. Opcionális Dátum szűrő

        if date_str:
            try:
                dt_start = datetime.strptime(date_str, '%Y/%m/%d').replace(tzinfo=timezone.utc)
                start_ts = dt_start.timestamp()
                end_ts = start_ts + 86399.999 
                
                # Hozzáadjuk az időkorlátot a lekérdezéshez
                key_condition = key_condition & Key('timestamp').between(Decimal(str(start_ts)), Decimal(str(end_ts)))
            except ValueError:
                return create_response(400, {'error': "Érvénytelen dátum formátum. Várt formátum: YYYY/MM/DD."})

        # 3. A varázslat: DynamoDB lekérdezés
        response = table.query(
            KeyConditionExpression=key_condition,
            ScanIndexForward=not is_desc, 
            Limit=limit 
        )

        raw_items = response.get('Items', [])

        # Visszaalakítjuk a DynamoDB sorokat az S3-as "fájl" formátumra a frontend miatt
        formatted_items = []
        for item in raw_items:
          
            approx_size_bytes = len(json.dumps(item, cls=DecimalEncoder))

            formatted_items.append({
                "key": f"dynamodb-record/{item.get('message_id', 'unknown')}", 
                "size": approx_size_bytes,                                    
                "last_modified": item.get('received_at', ''),                  
                "message_id": item.get('message_id', ''),
                "timestamp": item.get('timestamp', 0),
                "data": {                                                     
                    "joint_positions": item.get('joint_positions', []),
                    "timestamp": item.get('timestamp', 0)
                }
            })

        logger.info(f"Sikeresen lekérve és formázva {len(formatted_items)} rekord a DynamoDB-ből.")
        return create_response(200, formatted_items)

    except Exception as e:
        logger.error(f"Váratlan hiba történt: {e}", exc_info=True)
        return create_response(500, {'error': 'Belső szerverhiba történt.'})