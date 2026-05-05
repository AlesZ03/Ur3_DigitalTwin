import time
import threading
import queue
import json
import logging
import sys
import os  
import ssl
import boto3
import paho.mqtt.client as mqtt
import uuid 
from datetime import datetime, timezone
from rtde_control import RTDEControlInterface as RTDEControl
from rtde_receive import RTDEReceiveInterface as RTDEReceive

# --- Konfiguráció ---
ROBOT_IP = "192.168.98.6"  
#ROBOT_IP = "172.17.0.2" 
AWS_REGION = 'eu-central-1'

LOG_QUEUE_URL = 'https://sqs.eu-central-1.amazonaws.com/359289023072/Ur3_DigitalTwin-device-to-cloud'     

# AWS IoT Core (Paho MQTT)
AWS_IOT_ENDPOINT = "a13j85r7ze62nv-ats.iot.eu-central-1.amazonaws.com" 
CLIENT_ID = "UR3-Robot-001" 
IOT_SHADOW_UPDATE_TOPIC = f"$aws/things/{CLIENT_ID}/shadow/update"

IOT_TELEMETRY_TOPIC = "ur3/logs"
IOT_COMMAND_TOPIC = "ur3/commands"

# Tanúsítványok 
CERTS_DIR = "certs"
PATH_TO_ROOT_CA = os.path.join(CERTS_DIR, "AmazonRootCA1.pem")
PATH_TO_CERT = os.path.join(CERTS_DIR, "device.pem.crt")
PATH_TO_KEY = os.path.join(CERTS_DIR, "private.pem.key")

# --- Globális változók és események ---
command_queue = queue.Queue()
stop_event = threading.Event()

# --- Logging beállítása ---
def setup_logging():
    stream_handler = logging.StreamHandler(sys.stdout)
    formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
    stream_handler.setFormatter(formatter)
    
    root_logger = logging.getLogger()
    root_logger.setLevel(logging.INFO)
    root_logger.handlers.clear() 
    root_logger.addHandler(stream_handler)
    
    logging.getLogger('boto3').setLevel(logging.WARNING)
    logging.getLogger('botocore').setLevel(logging.WARNING)
    logging.getLogger('urllib3').setLevel(logging.WARNING)

# --- ÚJ: Telemetria küldő segédfüggvény ---
def send_telemetry(mqtt_client, joint_positions, current_timestamp):
    """Összeállítja a JSON-t és elküldi az MQTT-n keresztül az AWS IoT Core-ba."""
    try:
        dt_obj = datetime.fromtimestamp(current_timestamp, tz=timezone.utc)
        
        expire_timestamp = int(current_timestamp) + 86400
        
        telemetry_payload = {
            "message_id": str(uuid.uuid4()),
            "timestamp": dt_obj.strftime("%Y-%m-%d_%H-%M-%S"),
            "received_at": dt_obj.isoformat(),
            "expire_at": expire_timestamp, 
            "data": {
                "joint_positions": [round(p, 4) for p in joint_positions],
                "timestamp": current_timestamp
            }
        }
        telemetry_json = json.dumps(telemetry_payload)
       
        shadow_payload_dict = {
            "state": {
                "reported": {
                    "joint_positions": [round(p, 4) for p in joint_positions],
                    "timestamp": current_timestamp
                }
            }
        }
        shadow_payload_json = json.dumps(shadow_payload_dict)

        if mqtt_client and mqtt_client.is_connected():
            mqtt_client.publish(topic=IOT_SHADOW_UPDATE_TOPIC, payload=shadow_payload_json, qos=1)
            mqtt_client.publish(topic=IOT_TELEMETRY_TOPIC, payload=telemetry_json, qos=1)
            
    except Exception as e:
        logging.error(f"Hiba az MQTT publikálás során: {e}")


def data_sender(rtde_r, mqtt_client):
    logging.info("Adatküldő szál (Okos Tömörítéssel) elindult. ")
    
    last_sent_positions = None
    last_sampled_positions = None
    last_sent_time = 0
    
    is_resting = False
    MOVEMENT_INTERVAL = 0.1    
    MOVEMENT_THRESHOLD = 0.001  
    
    while not stop_event.is_set():
        try:
            current_positions = rtde_r.getActualQ()
            current_time = time.time()
            
            if current_positions is None:
                logging.warning("Nem sikerült lekérni a robot pozícióját.")
                time.sleep(0.05)
                continue

            # Legelső mérés: azonnal küldjük
            if last_sent_positions is None:
                send_telemetry(mqtt_client, current_positions, current_time)
                last_sent_positions = current_positions
                last_sampled_positions = current_positions
                last_sent_time = current_time
                continue

            # Kiszámoljuk az eltérést az utolsó KÜLDÖTT pozícióhoz képest
            max_diff = max(abs(c - s) for c, s in zip(current_positions, last_sent_positions))

            if max_diff > MOVEMENT_THRESHOLD:
                # --- A ROBOT MOZOG ---
                if is_resting:
          
                    anchor_time = current_time - 0.01
                    send_telemetry(mqtt_client, last_sampled_positions, anchor_time)
                    is_resting = False
                    logging.info("A robot elindult! Horgonypont elküldve az AWS-be.")

                if (current_time - last_sent_time) >= MOVEMENT_INTERVAL:
                    send_telemetry(mqtt_client, current_positions, current_time)
                    last_sent_positions = current_positions
                    last_sent_time = current_time
            
            else:
                if is_resting:
                    count +=1
                    #heartbeat
                    if(count ==20):
                        send_telemetry(mqtt_client, current_positions, current_time)
                        count = 0
                # --- A ROBOT ÁLL ---
                if not is_resting:
   
                    send_telemetry(mqtt_client, current_positions, current_time)
                    last_sent_positions = current_positions
                    last_sent_time = current_time
                    is_resting = True
                    count = 0
                    logging.info("A robot megállt. Adatküldés pihenő módba váltott.")

  
            last_sampled_positions = current_positions
            
      
            time.sleep(0.05)

        except Exception as e:
            logging.error(f"Hiba az adatküldő szálban: {e}", exc_info=True)
            time.sleep(1)
            
    logging.info("Adatküldő szál leállt.")

# --- MQTT Callback függvények ---
def on_connect(client, userdata, flags, rc, properties=None):
    if rc == 0:
        logging.info("Sikeresen csatlakozva az AWS IoT Core-hoz!")
        client.subscribe(IOT_COMMAND_TOPIC, qos=1)
        logging.info(f"Sikeresen feliratkozva a parancs topikra: {IOT_COMMAND_TOPIC}")
    else:
        logging.error(f"Csatlakozási hiba az AWS IoT Core-hoz, kód: {rc}.")

def on_message(client, userdata, msg):
    """Meghívódik, amikor üzenet érkezik a feliratkozott topikra (ur3/commands)."""
    try:
        payload_str = msg.payload.decode('utf-8')
        logging.info(f"MQTT parancs érkezett ({msg.topic}): {payload_str}")
        
        command_body = json.loads(payload_str)
        command_queue.put(command_body)
    except json.JSONDecodeError:
        logging.error(f"Hiba: A beérkezett MQTT üzenet nem valid JSON: {msg.payload}")
    except Exception as e:
        logging.error(f"Hiba a beérkezett MQTT parancs feldolgozása közben: {e}", exc_info=True)

# --- Fő program ---
def main():
    setup_logging()
    
    rtde_c = None
    rtde_r = None
    mqtt_client = None
    threads = []

    try:
        for i in range(5):
            try:
                logging.info(f"Kapcsolódás a robothoz ({ROBOT_IP})... ({i+1}. próbálkozás)")
                rtde_c = RTDEControl(ROBOT_IP)
                rtde_r = RTDEReceive(ROBOT_IP)
                if rtde_c.isConnected() and rtde_r.isConnected():
                    logging.info("Robot kapcsolat sikeres.")
                    break
                else:
                    raise ConnectionError("A robot RTDE interfészei nem jeleztek vissza sikeres kapcsolatot.")
            except Exception as e:
                logging.error(f"Robot csatlakozási hiba: {e}")
                if i == 4:
                    raise ConnectionError(f"Nem sikerült csatlakozni a robothoz ({ROBOT_IP}) 5 próbálkozás után.") from e
                time.sleep(5)

        for i in range(5):
            try:
                logging.info(f"MQTT kliens beállítása... ({i+1}. próbálkozás)")
                mqtt_client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=CLIENT_ID)
              
                mqtt_client.on_connect = on_connect
                mqtt_client.on_message = on_message 
                
                mqtt_client.tls_set(ca_certs=PATH_TO_ROOT_CA, certfile=PATH_TO_CERT, keyfile=PATH_TO_KEY,
                                    cert_reqs=ssl.CERT_REQUIRED, tls_version=ssl.PROTOCOL_TLSv1_2, ciphers=None)
                
                logging.info(f"Csatlakozás az AWS IoT végponthoz: {AWS_IOT_ENDPOINT}...")
                mqtt_client.connect(AWS_IOT_ENDPOINT, 8883, 60)
                mqtt_client.loop_start()

                break 
                

            except Exception as e:
                logging.error(f"MQTT csatlakozási hiba: {e}")
                if i == 4:
                    raise ConnectionError("Nem sikerült csatlakozni az AWS IoT Core-hoz 5 próbálkozás után.") from e
                time.sleep(5)

        threads = [
            threading.Thread(target=data_sender, name="DataSender", args=(rtde_r, mqtt_client))
        ]
        for t in threads:
            t.start()
        
        logging.info("A rendszer működik. A leállításhoz nyomj Ctrl+C-t.")
        
        while not stop_event.is_set():
            try:
                command_data = command_queue.get(timeout=1)
                command = command_data.get('command', command_data)
                
                if 'action' not in command:
                    logging.warning(f"Ismeretlen parancs (hiányzó 'action' kulcs): {command_data}")
                    continue

                action = command['action']
                if action == 'move':
                    speed = command.get('speed', 0.25)
                    acceleration = command.get('acceleration', 0.5)

                    if 'pose' in command:
                        target = command['pose']
                        if isinstance(target, list) and len(target) == 6:
                            logging.info(f"Lineáris mozgás (moveL) indítása: {target}")
                            rtde_c.moveL(target, speed, acceleration)
                            logging.info("Lineáris mozgás (moveL) befejezve.")
                        else:
                            logging.warning(f"Érvénytelen 'moveL' parancs: a 'pose' rossz formátumú. Kapott: {target}")
                    elif 'joints' in command:
                        target = command['joints']
                        if isinstance(target, list) and len(target) == 6:
                            joint_speed = command.get('speed', 1.05)
                            joint_acceleration = command.get('acceleration', 1.4)
                            logging.info(f"Csukló menti mozgás (moveJ) indítása: {target}")
                            rtde_c.moveJ(target, joint_speed, joint_acceleration)
                            logging.info("Csukló menti mozgás (moveJ) befejezve.")
                        else:
                            logging.warning(f"Érvénytelen 'moveJ' parancs: a 'joints' rossz formátumú. Kapott: {target}")
                    else:
                        logging.warning("Érvénytelen 'move' parancs: hiányzik a 'pose' vagy 'joints' kulcs.")
                
                elif action == 'stop':
                    logging.warning("Vészleállítás (stop) parancs fogadva! Mozgás lassítása...")
                    rtde_c.stopL(1.0) 
                    logging.info("Robot mozgása leállítva.")
                
                else:
                    logging.warning(f"Ismeretlen 'action' érték: {action}")

            except queue.Empty:
                continue
            except Exception as e:
                logging.error(f"Hiba a fő ciklusban parancsfeldolgozás közben: {e}", exc_info=True)

    except (KeyboardInterrupt, SystemExit):
        logging.info("\nLeállítás kérése (Ctrl+C vagy SystemExit)...")
    except Exception as e:
        logging.critical(f"Kritikus, nem kezelt hiba a fő programban: {e}", exc_info=True)
    finally:
        logging.info("A leállítási folyamat megkezdődött...")
        stop_event.set()
        
        for t in threads:
            if t.is_alive():
                logging.info(f"Várakozás a(z) '{t.name}' szál leállására...")
                t.join(timeout=5)
        
        if mqtt_client:
            logging.info("MQTT kapcsolat bontása.")
            mqtt_client.loop_stop()
            mqtt_client.disconnect()
        
        if rtde_c and rtde_c.isConnected():
            logging.info("Robot vezérlő kapcsolat bontása.")
            try:
                rtde_c.stopScript()
            except Exception as e:
                pass
            finally:
                rtde_c.disconnect()

        if rtde_r and rtde_r.isConnected():
            logging.info("Robot adatfogadó kapcsolat bontása.")
            rtde_r.disconnect()
            
        logging.info("Program leállt.")

if __name__ == "__main__":
    main()