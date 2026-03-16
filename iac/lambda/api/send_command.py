import json
import boto3
import os
import logging
from datetime import datetime, timezone
import uuid
import numpy as np

# Az új Layer-ből jövő könyvtárak
import ikfast_ur3 

# --- Konfiguráció és kliensek ---
logger = logging.getLogger()
logger.setLevel(logging.INFO)

sqs = boto3.client('sqs')
COMMAND_QUEUE_URL = os.getenv('COMMAND_QUEUE_URL')


UR3_IK = ikfast_ur3

# Központosított gyorsparancsok
QUICK_COMMANDS = [
    { 'label': 'Home Position', 'command': { 'action': 'move', 'joints': [0.0, -1.57, 1.57, -1.57, -1.57, 0.0] } },
    { 'label': 'Stop', 'command': { 'action': 'stop' } },
    { 'label': 'Test Position 1', 'command': { 'action': 'move', 'joints': [1.0, -1.8, 2.0, -1.7, -1.57, 0.0] } },
    { 'label': 'Test Position 2', 'command': { 'action': 'move', 'joints': [-1.0, -1.2, -2.0, -1.5, -1.57, 0.0] } }
]

CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'
}

# --- Segédfüggvények ---

def success_response(data, status_code=200):
    return {
        'statusCode': status_code,
        'headers': {**CORS_HEADERS, 'Content-Type': 'application/json'},
        'body': json.dumps(data)
    }

def error_response(status_code, message):
    return {
        'statusCode': status_code,
        'headers': {**CORS_HEADERS, 'Content-Type': 'application/json'},
        'body': json.dumps({'success': False, 'error': message})
    }

# --- Handler függvények ---

def handle_get_quick_commands(event):
    return success_response(QUICK_COMMANDS)

def handle_post_command(event):
    logger.info("Handling POST /command request.")
    body = json.loads(event['body']) if event.get('body') and isinstance(event['body'], str) else event.get('body', {})
    
    if 'command' not in body:
        return error_response(400, 'Missing "command" field')
    
    command = body['command']
    action = command.get('action')

    if action == 'move_xyz':
        try:
            # Jelenlegi ízületek beolvasása (ha küldi a kliens/robot)
            current_joints = command.get('current_joints')

            dof = ikfast_ur3.get_dof()
            free_dof = ikfast_ur3.get_free_dof()
            
            raw_xyz = command.get('target_xyz')
            if not raw_xyz or len(raw_xyz) != 3:
                return error_response(400, "target_xyz must be [x, y, z]")
            
            trans_list = [float(x) for x in raw_xyz]

            # 3x3 rotációs mátrix (lefelé néző szerszám)
            rot_list_nested = [
                [1.0, 0.0, 0.0],
                [0.0, 1.0, 0.0],
                [0.0, 0.0, 1.0]
            ]

            free_jt_vals = [0.0] * free_dof 

            logger.info(f"Hívás -> trans: {trans_list}, rot: {rot_list_nested}, free: {free_jt_vals}, pos: {current_joints}")
            
            solutions = ikfast_ur3.get_ik(trans_list, rot_list_nested, free_jt_vals)
            
            if solutions and len(solutions) > 0:
                # ---------------- ÚJ RÉSZ: A LEGJOBB MEGOLDÁS KIVÁLASZTÁSA ----------------
                if current_joints and len(current_joints) == dof:
                    # Kiszámoljuk a "távolságot" minden megoldás és a jelenlegi állapot között
                    # (Az ízületek közötti különbségek négyzeteinek összege)
                    def joint_distance(sol):
                        return sum((s - c) ** 2 for s, c in zip(sol, current_joints))
                    
                    # A legkisebb távolságú megoldás kiválasztása
                    best_sol = min(solutions, key=joint_distance)
                    logger.info("Okos választás: A jelenlegi pozícióhoz legközelebbi IK megoldás lett kiválasztva.")
                else:
                    # Ha nem kaptunk current_joints adatot, használjuk az elsőt, mint eddig
                    best_sol = solutions[0]
                    logger.info("Nem kaptunk 'current_joints' értéket, az első elérhető megoldást használjuk.")
                # -------------------------------------------------------------------------

                ik_command = {
                    'action': 'move',
                    'joints': [round(float(q), 5) for q in best_sol],
                    'speed': command.get('speed', 1.05),
                    'acceleration': command.get('acceleration', 1.4)
                }
                command = ik_command 
                logger.info(f"IKFast siker! Ízületek: {command['joints']}")
            else:
                return error_response(422, "Az IKFast nem talált megoldást a megadott koordinátákra és orientációra.")

        except Exception as e:
            logger.exception("Hiba az IK számítás közben")
            return error_response(500, f"Kinematikai hiba: {str(e)}")
    # --- SQS küldés (változatlan) ---
    message = {
        'command': command,
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'messageId': str(uuid.uuid4()),
        'source': 'ikfast_brain_lambda'
    }
    
    sqs.send_message(
        QueueUrl=COMMAND_QUEUE_URL,
        MessageBody=json.dumps(message)
    )
    
    return success_response({
        'success': True,
        'final_command': command
    })

def handle_get_status(event):
    response = sqs.get_queue_attributes(
        QueueUrl=COMMAND_QUEUE_URL,
        AttributeNames=['ApproximateNumberOfMessages']
    )
    return success_response({'pending': response.get('Attributes', {}).get('ApproximateNumberOfMessages', 0)})

# --- Fő belépési pont ---

def lambda_handler(event, context):
    if not COMMAND_QUEUE_URL:
        return error_response(500, 'Server configuration error: SQS URL missing.')

    http_method = event.get('httpMethod', 'GET').upper()
    path = event.get('path', '')

    if http_method == 'OPTIONS':
        return success_response({}, 204)

    try:
        if http_method == 'GET' and path.endswith('/quick'):
            return handle_get_quick_commands(event)
        elif http_method == 'POST' and (path.endswith('/command') or path.endswith('/command/')):
            return handle_post_command(event)
        elif http_method == 'GET' and path.endswith('/status'):
            return handle_get_status(event)
        else:
            return error_response(404, f"Not Found: {path}")
    except Exception as e:
        logger.exception('Unhandled error')
        return error_response(500, 'Internal server error.')