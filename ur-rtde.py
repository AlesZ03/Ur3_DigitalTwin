import time
import threading
import queue
import json
import boto3
from rtde_control import RTDEControlInterface as RTDEControl
from rtde_receive import RTDEReceiveInterface as RTDEReceive
import math

# --- Konfiguráció ---
ROBOT_IP = "172.17.0.2"  # <-- Robot IP címe
DEVICE_TO_CLOUD_URL = 'https://sqs.us-east-1.amazonaws.com/442729101031/ur3-digital-twin-device-to-cloud'
CLOUD_TO_DEVICE_URL = 'https://sqs.us-east-1.amazonaws.com/442729101031/ur3-digital-twin-cloud-to-device'
AWS_REGION = 'us-east-1'
POSITION_BATCH_SIZE = 10  # Hány üzenetet gyűjtsünk össze küldés előtt

# --- Globális változók és események ---
command_queue = queue.Queue()
stop_event = threading.Event()
sqs_client = boto3.client('sqs', region_name=AWS_REGION)

# --- Adatküldő szál ---
def data_sender(rtde_r):
    """
    Folyamatosan olvassa a robot pozícióját, és kötegelve küldi az SQS-be.
    """
    print("Adatküldő szál elindult.")
    message_batch = []
    
    while not stop_event.is_set():
        try:
            # Robot aktuális TCP pozíciójának lekérdezése
            tcp_pose = rtde_r.getActualTCPPose()
            # Robot státuszának lekérdezése (opcionális, itt 'moving'-ot használunk)
            robot_status = "moving" if rtde_r.isProtectiveStopped() == 0 else "stopped"

            message_body = {
                "position": [round(p, 4) for p in tcp_pose],
                "status": robot_status,
                "timestamp": time.time()
            }
            
            message_batch.append({
                'Id': str(len(message_batch)),
                'MessageBody': json.dumps(message_body)
            })

            # Ha a köteg elérte a kívánt méretet, küldjük el
            if len(message_batch) >= POSITION_BATCH_SIZE:
                print(f"{len(message_batch)} üzenet elküldése...")
                sqs_client.send_message_batch(
                    QueueUrl=DEVICE_TO_CLOUD_URL,
                    Entries=message_batch
                )
                message_batch = [] # Köteg kiürítése

            time.sleep(0.1) # Adatgyűjtési gyakoriság

        except Exception as e:
            print(f"Hiba az adatküldő szálban: {e}")
            time.sleep(1) # Hiba esetén várakozás

    print("Adatküldő szál leáll.")

# --- Parancsfogadó szál ---
def command_receiver():
    """
    Folyamatosan figyeli az SQS-t bejövő parancsokért.
    """
    print("Parancsfogadó szál elindult.")
    while not stop_event.is_set():
        try:
            response = sqs_client.receive_message(
                QueueUrl=CLOUD_TO_DEVICE_URL,
                MaxNumberOfMessages=1,
                WaitTimeSeconds=10, # Long-polling
                MessageAttributeNames=['All']
            )

            if 'Messages' in response:
                message = response['Messages'][0]
                receipt_handle = message['ReceiptHandle']
                
                try:
                    command_body = json.loads(message['Body'])
                    print(f"Parancs fogadva: {command_body}")
                    command_queue.put(command_body) # Parancs a sorba

                    # Üzenet törlése a sorból a feldolgozás után
                    sqs_client.delete_message(
                        QueueUrl=CLOUD_TO_DEVICE_URL,
                        ReceiptHandle=receipt_handle
                    )
                except json.JSONDecodeError:
                    print("Hiba: A beérkezett üzenet nem valid JSON.")
                except Exception as e:
                    print(f"Hiba a parancs feldolgozása közben: {e}")

        except Exception as e:
            print(f"Hiba a parancsfogadó szálban: {e}")
            time.sleep(1)
            
    print("Parancsfogadó szál leáll.")


# --- Fő program ---
def main():
    """
    Inicializálja a kapcsolatot, elindítja a szálakat és vezérli a robotot.
    """
    try:
        # Kapcsolódás a robothoz
        print(f"Kapcsolódás a robothoz ({ROBOT_IP})...")
        rtde_c = RTDEControl(ROBOT_IP)
        rtde_r = RTDEReceive(ROBOT_IP)
        print("Kapcsolat sikeres.")

        # Szálak létrehozása és indítása
        sender_thread = threading.Thread(target=data_sender, args=(rtde_r,))
        receiver_thread = threading.Thread(target=command_receiver)

        sender_thread.start()
        receiver_thread.start()
        
        # Fő ciklus a parancsok végrehajtására
        while not stop_event.is_set():
            try:
                # Várakozás új parancsra a sorban (nem blokkoló módon)
                command_data = command_queue.get_nowait()

                # A parancsot a 'command' kulcs alól vesszük ki, ha létezik
                command = command_data.get('command', command_data)
                
                if 'action' in command and command['action'] == 'move':
                    target_pose = command.get('pose')
                    speed = command.get('speed', 0.25)
                    acceleration = command.get('acceleration', 0.25)
                    
                    if target_pose and len(target_pose) == 6:
                        print(f"Mozgás a következő pozícióba: {target_pose}")
                        rtde_c.moveL(target_pose, speed, acceleration)
                    else:
                        print("Érvénytelen 'move' parancs: hiányzó vagy rossz formátumú 'pose'.")
                else:
                    # Hiba esetén a teljes, eredeti üzenetet írjuk ki
                    print(f"Ismeretlen parancs: {command_data}")

            except queue.Empty:
                # Nincs parancs, várakozunk egy kicsit
                time.sleep(0.1)
            
            except Exception as e:
                print(f"Hiba a fő ciklusban: {e}")

    except KeyboardInterrupt:
        print("\nLeállítás kérése (Ctrl+C)...")
    
    except Exception as e:
        print(f"Kritikus hiba a fő programban: {e}")

    finally:
        # Leállási jelzés küldése a szálaknak
        print("Szálak leállítása...")
        stop_event.set()
        
        # Szálak befejezésének megvárása
        sender_thread.join()
        receiver_thread.join()
        
        # Robot kapcsolat bontása
        if 'rtde_c' in locals() and rtde_c.isConnected():
            print("Robot vezérlő kapcsolat bontása.")
            rtde_c.disconnect()
        if 'rtde_r' in locals() and rtde_r.isConnected():
            print("Robot adatfogadó kapcsolat bontása.")
            rtde_r.disconnect()
            
        print("Program leállt.")

if __name__ == "__main__":
    main()
