import paho.mqtt.client as mqtt
import json
import time
import itertools
import ssl
import os
import sys

# --- Konfiguráció ---
# CSERÉLD LE A SAJÁT ENDPOINT CÍMEDRE! (AWS IoT Core -> Settings)
AWS_IOT_ENDPOINT = "a1xaharvzlkpl0-ats.iot.us-east-1.amazonaws.com" # <-- IDE ILLESZD BE A 'terraform output iot_endpoint' PARANCS KIMENETÉT!

# A topic, ahova küldünk
IOT_TOPIC = 'ur3/robot/telemetry'

# Egyedi azonosító a kliensnek
CLIENT_ID = "UR3-Robot-001"
PUBLISH_INTERVAL_SECONDS = 2  # Milyen gyakran küldjön adatot

# A letöltött tanúsítványok elérési útjai
CERTS_DIR = "certs"
PATH_TO_ROOT_CA = os.path.join(CERTS_DIR, "AmazonRootCA1.pem")
PATH_TO_CERT = os.path.join(CERTS_DIR, "device.pem.crt")
PATH_TO_KEY = os.path.join(CERTS_DIR, "private.pem.key")
ROOT_CA_URL = "https://www.amazontrust.com/repository/AmazonRootCA1.pem"

def ensure_certs_exist():
    """Ellenőrzi a tanúsítványfájlok meglétét, és letölti a Root CA-t, ha hiányzik."""
    os.makedirs(CERTS_DIR, exist_ok=True)

    if not os.path.exists(PATH_TO_ROOT_CA):
        print(f"Amazon Root CA nem található. Letöltés innen: {ROOT_CA_URL}...")
        try:
            import requests
            response = requests.get(ROOT_CA_URL)
            response.raise_for_status()
            with open(PATH_TO_ROOT_CA, "w") as f:
                f.write(response.text)
            print("Amazon Root CA sikeresen letöltve.")
        except ImportError:
            print("\nHIBA: A 'requests' csomag nincs telepítve.", file=sys.stderr)
            print("Kérlek telepítsd a következő paranccsal: pip install requests\n", file=sys.stderr)
            return False
        except Exception as e:
            print(f"\nHIBA: Az Amazon Root CA letöltése sikertelen: {e}", file=sys.stderr)
            print(f"Kérlek töltsd le manuálisan a fenti URL-ről és mentsd el ide: '{PATH_TO_ROOT_CA}'\n", file=sys.stderr)
            return False

    if not os.path.exists(PATH_TO_CERT) or not os.path.exists(PATH_TO_KEY):
        print(f"\nHIBA: Az eszköz tanúsítványa ({PATH_TO_CERT}) vagy privát kulcsa ({PATH_TO_KEY}) nem található.", file=sys.stderr)
        print("Kérlek futtasd a 'terraform apply' parancsot a legenerálásukhoz.\n", file=sys.stderr)
        return False
    
    return True
# --- MQTT Callback függvények ---

def on_connect(client, userdata, flags, rc):
    """Meghívódik, amikor a kliens sikeresen csatlakozik."""
    if rc == 0:
        print("Sikeresen csatlakozva az AWS IoT Core-hoz!")
    else:
        print(f"Csatlakozási hiba, kód: {rc}")

def on_publish(client, userdata, mid):
    """Meghívódik, amikor egy üzenet sikeresen publikálásra került."""
    print(f"Üzenet (mid: {mid}) sikeresen publikálva.")

def on_log(client, userdata, level, buf):
    """Részletes logolás a hibakereséshez."""
    print(f"Log: {buf}")

# --- Két pont, ami között a szimulált robot mozog ---
# Ezek a csuklók szögei radiánban.
# Pont A: Egyenesen előre, enyhén lefelé
point_a = [0.0, -1.57, 1.57, -1.57, -1.57, 0.0]
# Pont B: Oldalra, behajlítva
point_b = [1.0, -1.8, 2.0, -1.7, -1.57, 0.0]

# Váltakozó ciklus a két pont között
points_cycle = itertools.cycle([point_a, point_b])

def publish_position(client, joint_positions):
    """
    Publikál egy pozíciót az IoT Core topic-ra.
    """
    try:
        message_body = {
            "joint_positions": joint_positions,
            "timestamp": time.time()
        }
        payload = json.dumps(message_body)

        print(f"Üzenet küldése a '{IOT_TOPIC}' topic-ra: {payload}")
        
        # Üzenet küldése QoS 1-gyel (at least once delivery)
        client.publish(
            topic=IOT_TOPIC, 
            payload=payload, 
            qos=1
        )

    except Exception as e:
        print(f"Hiba az üzenet küldése közben: {e}")

def main():
    """
    Fő ciklus, ami periodikusan küldi a pozíció adatokat.
    """
    if not AWS_IOT_ENDPOINT:
        print("\nHIBA: Az 'AWS_IOT_ENDPOINT' nincs beállítva a core-test.py fájlban.", file=sys.stderr)
        print("Kérlek futtasd a 'terraform output iot_endpoint' parancsot és másold be az eredményt a szkriptbe.\n", file=sys.stderr)
        sys.exit(1)

    if not ensure_certs_exist():
        sys.exit(1)

    # MQTT kliens létrehozása
    # A CallbackAPIVersion.VERSION2 használata megszünteti a DeprecationWarning-ot
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=CLIENT_ID)

    # Callback függvények beállítása
    client.on_connect = on_connect
    client.on_publish = on_publish
    # client.on_log = on_log # Bekapcsolhatod a nagyon részletes hibakereséshez

    # TLS/SSL kapcsolat beállítása a tanúsítványokkal
    client.tls_set(ca_certs=PATH_TO_ROOT_CA,
                   certfile=PATH_TO_CERT,
                   keyfile=PATH_TO_KEY,
                   cert_reqs=ssl.CERT_REQUIRED,
                   tls_version=ssl.PROTOCOL_TLSv1_2,
                   ciphers=None)

    # Csatlakozás az AWS IoT végponthoz
    client.connect(AWS_IOT_ENDPOINT, 8883, 60)
    client.loop_start() # A hálózati forgalmat egy háttérszál kezeli

    print("\nTeszt szkript elindítva. Adatok küldése az IoT Core-nak.")
    print(f"A leállításhoz nyomj Ctrl+C-t.")
    
    try:
        while True:
            current_point = next(points_cycle)
            publish_position(client, current_point)
            time.sleep(PUBLISH_INTERVAL_SECONDS)
            
    except KeyboardInterrupt:
        print("\nSzkript leállítva.")
    finally:
        print("Kapcsolat bontása...")
        client.loop_stop()
        client.disconnect()

if __name__ == "__main__":
    main()