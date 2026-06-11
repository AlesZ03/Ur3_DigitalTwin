# UR3 Digital Twin on AWS

## Prerequisites
- Terraform (v1.5 or newer)
- AWS CLI v2 (with a configured IAM user, e.g., `aws configure`)
- Git
- Python 3.8+ on the edge device
- The robot's IP address must be accessible from the edge device.

---

## Installation and Operation (CI/CD Pipeline)

This project uses a CI/CD pipeline (GitHub Actions) for the automatic deployment and update of the infrastructure. The installation consists of two main phases: a one-time "bootstrap" phase and the continuous, automated deployment phase.

### Step 1: One-Time Setup (Bootstrap)

Before the main CI/CD pipeline can be used, a one-time "bootstrap" process must be executed. This process uses Terraform to create the essential AWS resources required for the secure and automated operation of the GitHub Actions pipeline.

**What does the bootstrap process create?**
*   **S3 Bucket:** For storing the Terraform state file (`.tfstate`) of the infrastructure managed by the CI/CD pipeline.
*   **DynamoDB Table:** For state file locking, which prevents concurrent, conflicting modifications.
*   **IAM Role for GitHub Actions:** A dedicated IAM role that allows the GitHub Actions pipeline to securely access the AWS account without keys.

**Running the bootstrap step-by-step:**

1.  **Navigate to the bootstrap directory:**
    ```bash
    cd iac/bootstrap
    ```

2.  **Initialize Terraform:**
    This command downloads the necessary AWS provider. The bootstrap process uses a local state file (`terraform.tfstate`) as it only needs to be run once.
    ```bash
    terraform init
    ```

3.  **Create the resources:**
    Run the `apply` command. Terraform will plan the changes and ask for your approval to create the resources. Type `yes` to confirm.
    ```bash
    terraform apply
    ```

4.  **Set up the GitHub Repository:**
    The output of the `terraform apply` command (`Outputs`) will display the details of the created resources. These values must be configured in the GitHub repository under `Settings -> Secrets and variables -> Actions`:
    *   **Secret (`AWS_ROLE_ARN`):** Copy the value of the `github_actions_role_arn` output here.
    *   **Variable (`AWS_REGION`):** The AWS region you are working in (e.g., `eu-central-1`).
    *   **Variable (`STATE_BUCKET_NAME`):** Copy the value of the `terraform_state_bucket_name` output here.

### Step 2: Infrastructure Deployment and Certificate Generation (CI/CD)

Once the bootstrap is complete and the GitHub repository is configured, the deployment of the main infrastructure is fully automated.

1.  **Push the Code:** Commit and push your changes to the `main` branch.
    ```bash
    git add .
    git commit -m "Ready to deploy main infrastructure"
    git push origin main
    ```

2.  **Monitor the Pipeline Execution:**
    The `push` event automatically triggers the GitHub Actions pipeline defined in the `.github/workflows/deploy.yml` file.
    -   The pipeline runs the `terraform init`, `plan`, and `apply` commands for the main (`iac`) infrastructure.
    -   This step creates the entire digital twin architecture: IoT Thing, Lambda functions, API Gateway, Kinesis, etc.
    -   During the run, Terraform generates the necessary certificates for the robot.
    -   At the end of the pipeline, the certificates (`.pem`, `.key`, `.crt`) are uploaded as an artifact named `robot-certs`.

3.  **Download the Results:**
    -   After a successful pipeline run, navigate to the summary page of that run on the GitHub Actions tab.
    -   In the "Artifacts" section, you will find the `robot-certs` package. Download and unzip it.
    -   In the pipeline log, at the end of the `Terraform Apply` step, look for the Terraform output variables (`Outputs`), especially the `iot_endpoint` and `iot_thing_name` values. Take note of them.

### Step 3: Edge Device Setup and Execution

This is the final step, where we prepare the device controlling the physical robot to communicate with the cloud.

1.  **Place the Certificates:**
    -   Copy the contents of the artifact downloaded and unzipped in Step 2 (`device.pem.crt`, `private.pem.key`, `AmazonRootCA1.pem`) into the project's `edge_device/certs/` directory.

2.  **Configure the Edge Script:**
    -   Open the `edge_device/ur-rtde.py` file.
    -   Set the following variables to their correct values:
        ```python
        # The robot's IP address on the local network
        ROBOT_IP = "192.168.1.100" 
        
        # The IoT endpoint obtained from the pipeline output
        AWS_IOT_ENDPOINT = "a123xyz-ats.iot.eu-central-1.amazonaws.com" 
        
        # The IoT Thing name obtained from the pipeline output
        CLIENT_ID = "UR3-Robot-001" 
        ```

3.  **Run the Script on the Edge Device:**
    -   Copy the entire `edge_device` directory to the device controlling the robot (e.g., a Raspberry Pi).
    -   Install the required Python packages:
        ```bash
        pip install paho-mqtt rtde
        ```
    -   Start the script:
        ```bash
        python edge_device/ur-rtde.py
        ```
    -   If everything is successful, you will see connection and data sending logs in the terminal.

---

## Infrastructure Teardown (CI/CD)

The infrastructure is torn down by manually triggering the GitHub Actions workflow, which runs a dedicated `destroy` job.

1.  In the GitHub repository, navigate to the **Actions** tab.
2.  In the left-hand menu, select the **"Terraform UR3 Pipeline"** workflow.
3.  Click the **"Run workflow"** button (on the `main` branch).
4.  The workflow will start, and because it was triggered manually (`workflow_dispatch`), only the `destroy` job will run, not the `terraform` job.
5.  The `destroy` job executes the `terraform destroy -auto-approve` command, which safely removes all AWS resources associated with the project.

---
---

# UR3 Digitális Iker AWS-en (Hungarian)


## Előfeltételek
- Terraform (v1.5 vagy újabb)
- AWS CLI v2 (konfigurált IAM felhasználóval, pl. `aws configure`)
- Git
- Python 3.8+ az edge eszközön
- A robot IP címe elérhető az edge eszközről.

---

## Telepítés és Működés (CI/CD Pipeline)

Ez a projekt egy CI/CD pipeline-t használ (GitHub Actions) az infrastruktúra automatikus telepítésére és frissítésére. A telepítés két fő szakaszból áll: egy egyszeri "bootstrap" fázisból és a folyamatos, automatizált deployment fázisból.

### 1. Lépés: Egyszeri Előkészületek (Bootstrap)

Mielőtt a fő CI/CD pipeline-t használni lehetne, egy egyszeri "bootstrap" folyamatot kell lefuttatni. Ez a folyamat Terraform segítségével hozza létre azokat az alapvető AWS erőforrásokat, amelyek a GitHub Actions pipeline biztonságos és automatizált működéséhez szükségesek.

**Mit hoz létre a bootstrap folyamat?**
*   **S3 Bucket:** A CI/CD pipeline által kezelt infrastruktúra Terraform állapotfájljának (`.tfstate`) tárolására.
*   **DynamoDB Tábla:** Az állapotfájl zárolásához, ami megakadályozza a párhuzamos, ütköző módosításokat.
*   **IAM Role for GitHub Actions:** Egy dedikált IAM szerepkör, ami lehetővé teszi, hogy a GitHub Actions pipeline biztonságosan, kulcsok nélkül hozzáférjen az AWS fiókhoz.

**A bootstrap futtatása lépésről lépésre:**

1.  **Navigáljon a bootstrap mappába:**
    ```bash
    cd iac/bootstrap
    ```

2.  **Inicializálja a Terraformot:**
    Ez a parancs letölti a szükséges AWS providert. A bootstrap folyamat helyi állapotfájlt (`terraform.tfstate`) használ, mivel csak egyszer kell lefuttatni.
    ```bash
    terraform init
    ```

3.  **Hozza létre az erőforrásokat:**
    Futtassa az `apply` parancsot. A Terraform megtervezi és a jóváhagyásod kéri az erőforrások létrehozásához. Írjon be `yes`-t a megerősítéshez.
    ```bash
    terraform apply
    ```

4.  **GitHub Repository Beállítása:**
    A `terraform apply` parancs kimenetében (`Outputs`) megjelennek a létrehozott erőforrások adatai. Ezeket az értékeket kell beállítani a GitHub repository `Settings -> Secrets and variables -> Actions` menüpontjában:
    *   **Secret (`AWS_ROLE_ARN`):** Ide másolja be a `github_actions_role_arn` kimenet értékét.
    *   **Variable (`AWS_REGION`):** Az AWS régió, ahol dolgozik (pl. `eu-central-1`).
    *   **Variable (`STATE_BUCKET_NAME`):** Ide másolja be a `terraform_state_bucket_name` kimenet értékét.

### 2. Lépés: Infrastruktúra Telepítése és Tanúsítványok Generálása (CI/CD)

Miután a bootstrap lefutott és a GitHub repository be van állítva, a fő infrastruktúra telepítése már teljesen automatizált.

1.  **Kód Feltöltése:** Véglegesítse és töltse fel a változtatásokat a `main` ágra.
    ```bash
    git add .
    git commit -m "Ready to deploy main infrastructure"
    git push origin main
    ```

2.  **Pipeline Futtatásának Megfigyelése:**
    A `push` esemény automatikusan elindítja a `.github/workflows/deploy.yml` fájlban definiált GitHub Actions pipeline-t.
    -   A pipeline lefuttatja a `terraform init`, `plan` és `apply` parancsokat a fő (`iac`) infrastruktúrára.
    -   Ez a lépés hozza létre a teljes digitális iker architektúrát: IoT Thing, Lambda függvények, API Gateway, Kinesis, stb.
    -   A Terraform futás közben legenerálja a robothoz szükséges tanúsítványokat.
    -   A pipeline végén a tanúsítványokat (`.pem`, `.key`, `.crt`) feltölti egy `robot-certs` nevű artifact-ként.

3.  **Eredmények Letöltése:**
    -   A sikeres pipeline futás után navigáljon a GitHub Actions fülön az adott futás összegző oldalára.
    -   Az "Artifacts" szekcióban találja a `robot-certs` csomagot. Töltse le és csomagolja ki.
    -   A pipeline logjában, a `Terraform Apply` lépés végén keresse meg a Terraform kimeneti változóit (`Outputs`), különösen az `iot_endpoint` és `iot_thing_name` értékeket. Jegyezze fel ezeket.

### 3. Lépés: Edge Eszköz Beállítása és Futtatása

Ez az utolsó lépés, ahol a fizikai robotot vezérlő eszközt felkészítjük a felhővel való kommunikációra.

1.  **Tanúsítványok Elhelyezése:**
    -   A 2. lépésben letöltött és kicsomagolt artifact tartalmát ( `device.pem.crt`, `private.pem.key`, `AmazonRootCA1.pem`) másolja be a projekt `edge_device/certs/` mappájába.

2.  **Edge Szkript Konfigurálása:**
    -   Nyissa meg a `edge_device/ur-rtde.py` fájlt.
    -   Állítsa be a következő változókat a megfelelő értékekre:
        ```python
        # A robot IP címe a helyi hálózaton
        ROBOT_IP = "192.168.1.100" 
        
        # A pipeline kimenetéből kapott IoT végpont
        AWS_IOT_ENDPOINT = "a123xyz-ats.iot.eu-central-1.amazonaws.com" 
        
        # A pipeline kimenetéből kapott IoT Thing név
        CLIENT_ID = "UR3-Robot-001" 
        ```

3.  **Szkript Futtatása az Edge Eszközön:**
    -   Másolja a teljes `edge_device` mappát a robotot vezérlő eszközre (pl. Raspberry Pi).
    -   Telepítse a szükséges Python csomagokat:
        ```bash
        pip install paho-mqtt rtde
        ```
    -   Indítsa el a szkriptet:
        ```bash
        python edge_device/ur-rtde.py
        ```
    -   Ha minden sikeres, a terminálban látni fogja a kapcsolódási és adatküldési logokat.

---

## Infrastruktúra Eltávolítása (CI/CD)

Az infrastruktúra eltávolítása a GitHub Actions workflow manuális elindításával történik, ami egy dedikált `destroy` feladatot futtat.

1.  A GitHub repository-ban navigáljon az **Actions** fülre.
2.  A bal oldali menüben válassza ki a **"Terraform UR3 Pipeline"** nevű workflow-t.
3.  Kattintson a **"Run workflow"** gombra (a `main` ágon).
4.  A workflow elindul, és mivel manuális (`workflow_dispatch`) indítás történt, a `terraform` job nem, csak a `destroy` job fog lefutni.
5.  A `destroy` job végrehajtja a `terraform destroy -auto-approve` parancsot, amely biztonságosan eltávolítja az összes, a projekthez tartozó AWS erőforrást.
