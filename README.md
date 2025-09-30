# UR3 Digital Twin on AWS

Ez a projekt egy **digitális iker** megvalósítása az **UR3 robotkarhoz**, amelyet az **Amazon AWS felhőszolgáltatóban** hozunk létre.  
A környezet infrastruktúráját **Terraform** kezeli és építi fel.

---

## Fő funkciók
- Digitális iker létrehozása UR3 robotkarhoz
- AWS szolgáltatások használata 
- Automatizált infrastruktúra-kezelés Terraformmal
- Könnyen bővíthető és újra-deployolható architektúra

---

## Előfeltételek
- [Terraform](https://developer.hashicorp.com/terraform/downloads) (≥ v1.5)
- AWS CLI (konfigurált felhasználóval, pl. `aws configure`)
- Git

---

## Telepítés lépései

1. **Repo klónozása**
   ```bash
   git clone https://github.com/<felhasznalo>/Ur3_DigitalTwin.git
   cd Ur3_DigitalTwin

2. **Terraform inicializálás**
    ```bash
    terraform init
3. **Konfiguráció ellenőrzése**
   ```bash
   terraform plan
4. **Infrastruktúra létrehozása**
  ```bash
   terraform apply
