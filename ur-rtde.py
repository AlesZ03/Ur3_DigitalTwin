import time
from rtde_control import RTDEControlInterface as RTDEControl
from rtde_receive import RTDEReceiveInterface as RTDEReceive
import math

ROBOT_IP = "172.17.0.2"  # <-- ezt cseréld a robot katedrális IP-jére

# Connect RTDE
rtde_c = RTDEControl(ROBOT_IP)
rtde_r = RTDEReceive(ROBOT_IP)

pos_a = [0, -1.57, 1.57, 0, 1.57, 0]# koordináta 1
pos_b = [0, -1.57, -1.57, 0, 1.57, 0] 

tolerance = 0.01
# Get current joint positions
def distance(p1, p2):
    """Egyszerű Euklidesz távolság a TCP koordináták között"""
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(p1, p2)))

try:
    while True:
        # Menj pos_a-ra
        rtde_c.moveL(pos_a, 0.25, 0.25)  # sebesség és gyorsulás
        # Várjuk el, hogy odaérjen
        while distance(rtde_r.getActualTCPPose(), pos_a) > tolerance:
            time.sleep(0.05)
            print(rtde_r.getActualQ())
        
        print("Elértük az A pontot, várakozás 1 mp")
        time.sleep(1)

        # Menj pos_b-re
        rtde_c.moveL(pos_b, 0.25, 0.25)
        while distance(rtde_r.getActualTCPPose(), pos_b) > tolerance:
            time.sleep(0.05)
            print(rtde_r.getActualQ())
        
        print("Elértük a B pontot, várakozás 1 mp")
        time.sleep(1)

except KeyboardInterrupt:
    print("Leállítás...")
finally:
    rtde_c.disconnect()
    rtde_r.disconnect()
