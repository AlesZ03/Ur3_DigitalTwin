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
from rtde_control import RTDEControlInterface as RTDEControl
from rtde_receive import RTDEReceiveInterface as RTDEReceive

# --- Konfiguráció ---
#ROBOT_IP = "192.168.98.6"  
ROBOT_IP = "172.17.0.2" 
AWS_REGION = 'us-east-1'

# SQS Sorok 
COMMAND_QUEUE_URL = 'https://sqs.us-east-1.amazonaws.com/359289023072/ur3-digital-twin-cloud-to-device' 
LOG_QUEUE_URL = 'https://sqs.us-east-1.amazonaws.com/359289023072/ur3-digital-twin-device-to-cloud'     

# AWS IoT Core (Paho MQTT)
AWS_IOT_ENDPOINT = "a13j85r7ze62nv-ats.iot.us-east-1.amazonaws.com" 
IOT_TOPIC_TELEMETRY = 'ur3/robot/telemetry'
CLIENT_ID = "UR3-Robot-001" 

# Tanúsítványok (a Terraform generálja őket)
CERTS_DIR = "certs"
PATH_TO_ROOT_CA = os.path.join(CERTS_DIR, "AmazonRootCA1.pem")
PATH_TO_CERT = os.path.join(CERTS_DIR, "device.pem.crt")
PATH_TO_KEY = os.path.join(CERTS_DIR, "private.pem.key")

# --- Globális változók és események ---
command_queue = queue.Queue()
stop_event = threading.Event()

# --- Logging beállítása ---
def setup_logging():
    """Beállítja a Python logging modult, hogy a logokat a konzolra küldje."""
    stream_handler = logging.StreamHandler(sys.stdout)
    formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
    stream_handler.setFormatter(formatter)
    
    root_logger = logging.getLogger()
    root_logger.setLevel(logging.INFO)
    root_logger.handlers.clear() 
    root_logger.addHandler(stream_handler)
    
    # Külső könyvtárak logjainak halkítása
    logging.getLogger('boto3').setLevel(logging.WARNING)
    logging.getLogger('botocore').setLevel(logging.WARNING)
    logging.getLogger('urllib3').setLevel(logging.WARNING)

# --- Adatküldő szál (telemetria) ---
def data_sender(rtde_r, mqtt_client):
    """Folyamatosan olvassa a robot pozícióját, és küldi az AWS IoT Core-ra (valós idejű) és SQS-be (historikus)."""
    sqs = boto3.client('sqs', region_name=AWS_REGION)
    logging.info("Adatküldő szál (telemetria) elindult.")
    while not stop_event.is_set():
        try:
            joint_positions = rtde_r.getActualQ()
            if joint_positions is None:
                logging.warning("Nem sikerült lekérni a robot pozícióját (getActualQ: None).")
                time.sleep(1)
                continue

            message_body = {
                "joint_positions": [round(p, 4) for p in joint_positions],
                "timestamp": time.time()
            }
            payload = json.dumps(message_body)

            if mqtt_client and mqtt_client.is_connected():
                mqtt_client.publish(
                    topic=IOT_TOPIC_TELEMETRY,
                    payload=payload,
                    qos=1
                )
            else:
                logging.warning("MQTT kliens nincs csatlakozva, a valós idejű telemetria küldés szünetel...")

  
            sqs.send_message(QueueUrl=LOG_QUEUE_URL, MessageBody=payload)

            time.sleep(0.1)  
        except Exception as e:
            logging.error(f"Hiba az adatküldő szálban: {e}", exc_info=True)
            time.sleep(1)
    logging.info("Adatküldő szál leállt.")

def command_receiver():
    """Folyamatosan figyeli az SQS-t bejövő parancsokért."""
    sqs = boto3.client('sqs', region_name=AWS_REGION)
    logging.info("Parancsfogadó szál elindult.")
    while not stop_event.is_set():
        try:
            response = sqs.receive_message(
                QueueUrl=COMMAND_QUEUE_URL,
                MaxNumberOfMessages=1,
                WaitTimeSeconds=10,
                MessageAttributeNames=['All']
            )
            if 'Messages' in response:
                message = response['Messages'][0]
                receipt_handle = message['ReceiptHandle']
                try:
                    command_body = json.loads(message['Body'])
                    logging.info(f"Parancs fogadva: {command_body}")
                    command_queue.put(command_body)
                    sqs.delete_message(QueueUrl=COMMAND_QUEUE_URL, ReceiptHandle=receipt_handle)
                except json.JSONDecodeError:
                    logging.error(f"Hiba: A beérkezett üzenet nem valid JSON: {message['Body']}")

                    sqs.delete_message(QueueUrl=COMMAND_QUEUE_URL, ReceiptHandle=receipt_handle)
                except Exception as e:
                    logging.error(f"Hiba a parancs feldolgozása közben: {e}", exc_info=True)
        except Exception as e:
            logging.error(f"Hiba a parancsfogadó szálban: {e}", exc_info=True)
            time.sleep(5) 
    logging.info("Parancsfogadó szál leállt.")

# --- MQTT Callback függvények ---
def on_connect(client, userdata, flags, rc, properties=None):
    """Meghívódik, amikor a kliens csatlakozik az AWS IoT-hoz."""
    if rc == 0:
        logging.info("Sikeresen csatlakozva az AWS IoT Core-hoz!")
    else:
        
        logging.error(f"Csatlakozási hiba az AWS IoT Core-hoz, kód: {rc}. Lehetséges okok: 1: hibás protokoll, 2: hibás kliens ID, 3: szerver nem elérhető, 4: hibás felhasználónév/jelszó, 5: nincs jogosultság.")

# --- Fő program ---
def main():
    """Inicializálja a kapcsolatot, elindítja a szálakat és vezérli a robotot."""
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
                mqtt_client.tls_set(ca_certs=PATH_TO_ROOT_CA, certfile=PATH_TO_CERT, keyfile=PATH_TO_KEY,
                                    cert_reqs=ssl.CERT_REQUIRED, tls_version=ssl.PROTOCOL_TLSv1_2, ciphers=None)
                logging.info(f"Csatlakozás az AWS IoT végponthoz: {AWS_IOT_ENDPOINT}...")
                mqtt_client.connect(AWS_IOT_ENDPOINT, 8883, 60)
                mqtt_client.loop_start()

                time.sleep(2)
                if mqtt_client.is_connected():
                    logging.info("MQTT kapcsolat sikeresen elindítva.")
                    break
                else:
                    mqtt_client.loop_stop(force=True)
                    raise ConnectionError("Az MQTT kliens nem csatlakozott a várakozási idő alatt.")
            except Exception as e:
                logging.error(f"MQTT csatlakozási hiba: {e}")
                if i == 4:
                    raise ConnectionError("Nem sikerült csatlakozni az AWS IoT Core-hoz 5 próbálkozás után.") from e
                time.sleep(5)


        threads = [
            threading.Thread(target=data_sender, name="DataSender", args=(rtde_r, mqtt_client)),
            threading.Thread(target=command_receiver, name="CommandReceiver")
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
                if t.is_alive():
                    logging.warning(f"A(z) '{t.name}' szál nem állt le időben.")
        
        if mqtt_client:
            logging.info("MQTT kapcsolat bontása.")
            mqtt_client.loop_stop()
            mqtt_client.disconnect()
        
        if rtde_c and rtde_c.isConnected():
            logging.info("Robot vezérlő kapcsolat bontása.")
            try:
                rtde_c.stopScript()
            except Exception as e:
                logging.error(f"Hiba a robot script leállítása közben: {e}")
            finally:
                rtde_c.disconnect()

        if rtde_r and rtde_r.isConnected():
            logging.info("Robot adatfogadó kapcsolat bontása.")
            rtde_r.disconnect()
            
        logging.info("Program leállt.")

if __name__ == "__main__":
    main()
