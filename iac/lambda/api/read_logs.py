import json
import boto3
import os
import logging
from datetime import datetime
from botocore.config import Config
from concurrent.futures import ThreadPoolExecutor, as_completed

# Logging beállítása
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Kliensek inicializálása a handleren kívül (teljesítmény optimalizálás)
# A boto3 kliens konfigurálása a megnövelt connection pool mérethez.
# Ennek egyeznie kell vagy nagyobbnak kell lennie, mint a ThreadPoolExecutor max_workers értéke.
boto_config = Config(max_pool_connections=25)
s3_client = boto3.client('s3', config=boto_config)
S3_BUCKET_NAME = os.environ.get('S3_BUCKET_NAME')


# --- CORS Fejlécek ---
# Fejlesztéshez a '*' megfelelő, de éles környezetben érdemes
# az Amplify domainre korlátozni: 'https://<your-app>.amplifyapp.com'
CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'
}

def create_response(status_code, body):
    """Segédfüggvény a konzisztens API Gateway válaszok létrehozásához."""
    return {
        'statusCode': status_code,
        'headers': CORS_HEADERS,
        'body': json.dumps(body, default=str) # A default=str kezeli a datetime objektumokat
    }

def fetch_log_content(log_meta):
    """
    Párhuzamosan futtatható segédfüggvény, ami letölt és feldolgoz egyetlen log fájlt.
    """
    try:
        s3_object = s3_client.get_object(Bucket=S3_BUCKET_NAME, Key=log_meta['key'])
        content = s3_object['Body'].read().decode('utf-8')
        log_data = json.loads(content)
        
        # Metaadatok és a tartalom egyesítése
        return {
            'key': log_meta['key'],
            'size': log_meta['size'],
            'last_modified': log_meta['last_modified'], # A későbbi rendezéshez kell
            **log_data
        }
    except Exception as e:
        logger.warning(f"Nem sikerült beolvasni vagy feldolgozni az objektumot ({log_meta['key']}): {e}")
        return None

def lambda_handler(event, context):
    """
    Ez a Lambda kezeli a /logs végpontra érkező GET kéréseket.
    Listázza a log fájlokat egy S3 bucketből egy adott dátumra.
    Kezeli a CORS preflight OPTIONS kéréseket is.
    """
    logger.info(f"Esemény fogadva: {json.dumps(event)}")

    # --- CORS Preflight Kérés Kezelése ---
    http_method = event.get('httpMethod', 'GET').upper()
    if http_method == 'OPTIONS':
        logger.info("OPTIONS preflight kérés kezelése.")
        return create_response(200, {"message": "CORS preflight check sikeres"})

    # --- Fő Logika (GET kérés) ---
    if not S3_BUCKET_NAME:
        logger.error("KRITIKUS HIBA: Az S3_BUCKET_NAME környezeti változó nincs beállítva.")
        return create_response(500, {'error': 'Szerver konfigurációs hiba.'})

    try:
        # Query paraméterek kinyerése
        params = event.get('queryStringParameters') or {}
        date_str = params.get('date') # Várt formátum: YYYY/MM/DD
        limit = int(params.get('limit', 50))
        order = params.get('order', 'desc').lower()

        if not date_str:
            return create_response(400, {'error': "Hiányzó 'date' query paraméter."})

        # Dátum validálása és S3 prefix összeállítása
        try:
            datetime.strptime(date_str, '%Y/%m/%d')
            s3_prefix = f"robot-data/{date_str}/"
        except ValueError:
            return create_response(400, {'error': "Érvénytelen dátum formátum. Várt formátum: YYYY/MM/DD."})

        logger.info(f"Objektumok listázása: bucket='{S3_BUCKET_NAME}', prefix='{s3_prefix}'")

        # 1. Objektum metaadatok listázása S3-ból (ez gyors)
        paginator = s3_client.get_paginator('list_objects_v2')
        pages = paginator.paginate(Bucket=S3_BUCKET_NAME, Prefix=s3_prefix)
        
        all_logs_meta = []
        for page in pages:
            if 'Contents' in page:
                for obj in page['Contents']:
                    all_logs_meta.append({
                        'key': obj['Key'],
                        'last_modified': obj['LastModified'],
                        'size': obj['Size']
                    })
        
        # 2. Eredmények rendezése a letöltés előtt, hogy a legfrissebbeket kérjük le
        is_desc = (order == 'desc')
        sorted_logs_meta = sorted(all_logs_meta, key=lambda x: x['last_modified'], reverse=is_desc)

        # 3. Limitálás a kért darabszámra
        metas_to_fetch = sorted_logs_meta[:limit]

        # 4. A logok tartalmának párhuzamos letöltése
        final_logs = []
        with ThreadPoolExecutor(max_workers=20) as executor:
            future_to_log = {executor.submit(fetch_log_content, meta): meta for meta in metas_to_fetch}
            for future in as_completed(future_to_log):
                result = future.result()
                if result:  # Csak a sikeresen letöltötteket adjuk hozzá
                    final_logs.append(result)
        
        # 5. A végső lista rendezése, mivel a párhuzamos feldolgozás nem garantálja a sorrendet
        final_sorted_logs = sorted(final_logs, key=lambda x: x['last_modified'], reverse=is_desc)

        logger.info(f"Sikeresen lekérve és feldolgozva {len(final_sorted_logs)} log.")
        return create_response(200, final_sorted_logs)

    except Exception as e:
        logger.error(f"Váratlan hiba történt: {e}", exc_info=True)
        return create_response(500, {'error': 'Belső szerverhiba történt.'})
