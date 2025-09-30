# Állítsd be a régiót
export AWS_DEFAULT_REGION=eu-central-1

aws iottwinmaker create-workspace \
  --workspace-id ur3-workspace-2 \
  --s3-location arn:aws:s3:::my-twinmaker-bucket \
  --role arn:aws:iam::123456789012:role/MyTwinMakerRole


# Egyszerű component type (lambda nélkül először)
aws iottwinmaker create-component-type \
  --workspace-id ur3-workspace-2 \
  --component-type-id com.ur3.robot.simple \
  --description "Simple UR3 Robot Component" \
  --property-definitions '{
    "joint1_position": {
      "dataType": {"type": "DOUBLE"},
      "isTimeSeries": false,
      "defaultValue": {"doubleValue": 0.0}
    },
    "joint2_position": {
      "dataType": {"type": "DOUBLE"},
      "isTimeSeries": false,
      "defaultValue": {"doubleValue": 0.0}
    },
    "robot_status": {
      "dataType": {"type": "STRING"},
      "isTimeSeries": false,
      "defaultValue": {"stringValue": "IDLE"}
    }
  }'

# Entity létrehozása
aws iottwinmaker create-entity \
  --workspace-id ur3-workspace-2 \
  --entity-id ur3-robot-002 \
  --entity-name "UR3 Robot 002" \
  --components '{
    "ur3_telemetry": {
      "componentTypeId": "com.ur3.robot.simple",
      "properties": {
        "joint1_position": {"value": {"doubleValue": 0.0}},
        "joint2_position": {"value": {"doubleValue": 0.0}},
        "robot_status": {"value": {"stringValue": "IDLE"}}
      }
    }
  }'

# Tesztelés
aws iottwinmaker get-entity \
  --workspace-id ur3-workspace-2 \
  --entity-id ur3-robot-002