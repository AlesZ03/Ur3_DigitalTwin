import json
import boto3
import logging
import os
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize AWS clients
twinmaker = boto3.client('iottwinmaker')
iot_data = boto3.client('iot-data')

# Environment variables
WORKSPACE_ID = os.environ.get('WORKSPACE_ID', 'ur3-workspace-terraform')
ENTITY_ID = os.environ.get('ENTITY_ID', 'ur3-robot-001')
S3_BUCKET = os.environ.get('S3_BUCKET', '')

def lambda_handler(event, context):
    """
    Main Lambda handler for TwinMaker data connector
    Handles both IoT telemetry data and TwinMaker property requests
    """
    try:
        logger.info(f"Received event: {json.dumps(event, default=str)}")
        
        # Check if this is a TwinMaker property value request
        if 'selectedProperties' in event:
            return handle_twinmaker_request(event, context)
        
        # Otherwise, handle IoT telemetry data
        return handle_iot_telemetry(event, context)
        
    except Exception as e:
        logger.error(f"Error in lambda_handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to process request'
            })
        }

def handle_twinmaker_request(event, context):
    """
    Handle TwinMaker property value requests (data connector function)
    """
    try:
        logger.info("Handling TwinMaker property request")
        
        workspace_id = event.get('workspaceId', WORKSPACE_ID)
        entity_id = event.get('entityId', ENTITY_ID)
        component_name = event.get('componentName', 'ur3_telemetry')
        selected_properties = event.get('selectedProperties', [])
        
        # Generate mock telemetry data or fetch from external source
        property_values = {}
        current_time = datetime.now(timezone.utc)
        
        for prop in selected_properties:
            if prop == 'joint1_position':
                property_values[prop] = {
                    'propertyValue': {
                        'time': current_time.isoformat(),
                        'value': {'doubleValue': get_joint_position(1)}
                    }
                }
            elif prop == 'joint2_position':
                property_values[prop] = {
                    'propertyValue': {
                        'time': current_time.isoformat(),
                        'value': {'doubleValue': get_joint_position(2)}
                    }
                }
            elif prop == 'joint3_position':
                property_values[prop] = {
                    'propertyValue': {
                        'time': current_time.isoformat(),
                        'value': {'doubleValue': get_joint_position(3)}
                    }
                }
            elif prop == 'robot_status':
                property_values[prop] = {
                    'propertyValue': {
                        'time': current_time.isoformat(),
                        'value': {'stringValue': get_robot_status()}
                    }
                }
            elif prop.endswith('_target'):
                joint_num = prop.split('_')[0][-1]
                property_values[prop] = {
                    'propertyValue': {
                        'time': current_time.isoformat(),
                        'value': {'doubleValue': get_target_position(int(joint_num))}
                    }
                }
        
        logger.info(f"Returning property values: {property_values}")
        
        return {
            'statusCode': 200,
            'propertyValues': property_values
        }
        
    except Exception as e:
        logger.error(f"Error handling TwinMaker request: {str(e)}")
        return {
            'statusCode': 500,
            'propertyValues': {}
        }

def handle_iot_telemetry(event, context):
    """
    Handle IoT telemetry data updates
    """
    try:
        logger.info("Handling IoT telemetry data")
        
        # Parse IoT message based on event structure
        telemetry_data = extract_telemetry_data(event)
        
        if not telemetry_data:
            logger.warning("No valid telemetry data found in event")
            return {
                'statusCode': 200,
                'body': json.dumps('No telemetry data to process')
            }
        
        # Update TwinMaker entity properties
        update_result = update_twinmaker_entity(telemetry_data)
        
        # Send control commands based on current state
        command_result = process_control_logic(telemetry_data)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Successfully processed telemetry data',
                'update_result': update_result,
                'command_result': command_result
            })
        }
        
    except Exception as e:
        logger.error(f"Error handling IoT telemetry: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error processing telemetry: {str(e)}')
        }

def extract_telemetry_data(event) -> Optional[Dict[str, Any]]:
    """
    Extract telemetry data from various event formats
    """
    try:
        # Direct IoT message
        if all(key in event for key in ['joint1_position', 'joint2_position', 'joint3_position']):
            return event
            
        # IoT Rules format
        if 'Records' in event:
            for record in event['Records']:
                if 'body' in record:
                    data = json.loads(record['body'])
                    if 'joint1_position' in data:
                        return data
                elif 'joint1_position' in record:
                    return record
                    
        # AWS IoT message format
        if 'messageId' in event and any(key.startswith('joint') for key in event.keys()):
            return {k: v for k, v in event.items() if not k.startswith('messageId') and not k.startswith('timestamp')}
            
        return None
        
    except Exception as e:
        logger.error(f"Error extracting telemetry data: {str(e)}")
        return None

def update_twinmaker_entity(telemetry_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Update TwinMaker entity properties with telemetry data
    """
    try:
        current_time = datetime.now(timezone.utc).isoformat()
        property_updates = {}
        
        # Map telemetry data to property updates
        property_mapping = {
            'joint1_position': 'doubleValue',
            'joint2_position': 'doubleValue', 
            'joint3_position': 'doubleValue',
            'robot_status': 'stringValue'
        }
        
        for prop_name, value_type in property_mapping.items():
            if prop_name in telemetry_data:
                if value_type == 'doubleValue':
                    property_updates[prop_name] = {
                        'value': {'doubleValue': float(telemetry_data[prop_name])},
                        'timestamp': current_time
                    }
                elif value_type == 'stringValue':
                    property_updates[prop_name] = {
                        'value': {'stringValue': str(telemetry_data[prop_name])},
                        'timestamp': current_time
                    }
        
        if not property_updates:
            logger.warning("No valid properties to update")
            return {'status': 'no_updates'}
        
        logger.info(f"Updating entity {ENTITY_ID} with properties: {list(property_updates.keys())}")
        
        # Update TwinMaker entity
        response = twinmaker.update_entity(
            workspaceId=WORKSPACE_ID,
            entityId=ENTITY_ID,
            componentUpdates={
                'ur3_telemetry': {
                    'updateType': 'UPDATE',
                    'propertyUpdates': property_updates
                }
            }
        )
        
        logger.info(f"TwinMaker update successful: {response}")
        return {'status': 'success', 'updated_properties': list(property_updates.keys())}
        
    except Exception as e:
        logger.error(f"Error updating TwinMaker entity: {str(e)}")
        return {'status': 'error', 'error': str(e)}

def process_control_logic(telemetry_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process control logic and send commands to robot
    """
    try:
        robot_status = telemetry_data.get('robot_status', 'UNKNOWN')
        current_positions = [
            telemetry_data.get('joint1_position', 0.0),
            telemetry_data.get('joint2_position', 0.0),
            telemetry_data.get('joint3_position', 0.0)
        ]
        
        commands_sent = []
        
        # Simple control logic examples
        if robot_status == 'IDLE':
            # Send a simple movement command
            command = {
                'command_type': 'move_joints',
                'joint_targets': {
                    'joint1': 0.785,  # 45 degrees
                    'joint2': -0.524, # -30 degrees
                    'joint3': 0.524   # 30 degrees
                },
                'speed': 0.1,
                'timestamp': datetime.now(timezone.utc).isoformat()
            }
            
            publish_result = publish_robot_command(command)
            commands_sent.append({'command': 'move_joints', 'result': publish_result})
            
        elif robot_status == 'MOVING':
            # Check if robot is close to targets, send stop if needed
            targets = [0.785, -0.524, 0.524]  # Example targets
            if all(abs(current - target) < 0.05 for current, target in zip(current_positions, targets)):
                stop_command = {
                    'command_type': 'stop',
                    'timestamp': datetime.now(timezone.utc).isoformat()
                }
                
                publish_result = publish_robot_command(stop_command)
                commands_sent.append({'command': 'stop', 'result': publish_result})
                
        elif robot_status == 'ERROR':
            # Send reset command
            reset_command = {
                'command_type': 'reset',
                'timestamp': datetime.now(timezone.utc).isoformat()
            }
            
            publish_result = publish_robot_command(reset_command)
            commands_sent.append({'command': 'reset', 'result': publish_result})
        
        return {'status': 'success', 'commands_sent': commands_sent}
        
    except Exception as e:
        logger.error(f"Error in control logic: {str(e)}")
        return {'status': 'error', 'error': str(e)}

def publish_robot_command(command: Dict[str, Any]) -> Dict[str, Any]:
    """
    Publish command to robot via IoT Core
    """
    try:
        topic = 'ur3/robot/commands'
        payload = json.dumps(command)
        
        response = iot_data.publish(
            topic=topic,
            qos=1,
            payload=payload
        )
        
        logger.info(f"Published command to {topic}: {command}")
        return {'status': 'success', 'messageId': response.get('messageId')}
        
    except Exception as e:
        logger.error(f"Error publishing command: {str(e)}")
        return {'status': 'error', 'error': str(e)}

def get_joint_position(joint_number: int) -> float:
    """
    Get current joint position (mock implementation)
    In real implementation, this would fetch from external system
    """
    import math
    import time
    
    # Generate realistic joint positions with some movement
    base_positions = [0.0, -1.57, 1.57]  # Base positions for joints 1, 2, 3
    time_factor = time.time() * 0.1  # Slow oscillation
    
    if joint_number <= len(base_positions):
        base_pos = base_positions[joint_number - 1]
        # Add small oscillation
        return base_pos + 0.2 * math.sin(time_factor + joint_number)
    
    return 0.0

def get_target_position(joint_number: int) -> float:
    """
    Get target position for joint (mock implementation)
    """
    target_positions = [0.785, -0.524, 0.524]  # Target positions
    
    if joint_number <= len(target_positions):
        return target_positions[joint_number - 1]
    
    return 0.0

def get_robot_status() -> str:
    """
    Get current robot status (mock implementation)
    """
    import random
    import time
    
    # Cycle through statuses based on time
    cycle_time = int(time.time()) % 30  # 30 second cycle
    
    if cycle_time < 10:
        return 'IDLE'
    elif cycle_time < 25:
        return 'MOVING'
    else:
        return 'IDLE'

# Additional utility functions
def validate_telemetry_data(data: Dict[str, Any]) -> bool:
    """
    Validate incoming telemetry data
    """
    required_fields = ['joint1_position', 'joint2_position', 'joint3_position']
    return all(field in data for field in required_fields)

def format_property_value(value: Any, data_type: str) -> Dict[str, Any]:
    """
    Format property value according to TwinMaker requirements
    """
    if data_type == 'DOUBLE':
        return {'doubleValue': float(value)}
    elif data_type == 'STRING':
        return {'stringValue': str(value)}
    elif data_type == 'BOOLEAN':
        return {'booleanValue': bool(value)}
    elif data_type == 'INTEGER':
        return {'integerValue': int(value)}
    else:
        return {'stringValue': str(value)}