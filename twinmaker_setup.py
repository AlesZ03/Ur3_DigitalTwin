#!/usr/bin/env python3
"""
TwinMaker Setup Script
Separates TwinMaker resource creation from Terraform infrastructure
"""

import boto3
import json
import time
import sys
from typing import Dict, Any
from botocore.exceptions import ClientError

class TwinMakerSetup:
    def __init__(self, region: str, workspace_id: str, entity_id: str, 
                 scene_id: str, role_arn: str, s3_bucket: str, lambda_arn: str):
        self.region = region
        self.workspace_id = workspace_id
        self.entity_id = entity_id
        self.scene_id = scene_id
        self.role_arn = role_arn
        self.s3_bucket = s3_bucket
        self.lambda_arn = lambda_arn
        
        self.client = boto3.client('iottwinmaker', region_name=region)
        self.s3_client = boto3.client('s3', region_name=region)
    
    def create_workspace(self) -> bool:
        """Create or verify TwinMaker workspace"""
        try:
            response = self.client.get_workspace(workspaceId=self.workspace_id)
            print(f"Workspace {self.workspace_id} already exists")
            return True
        except ClientError as e:
            if e.response['Error']['Code'] != 'ResourceNotFoundException':
                raise
        
        print(f"Creating workspace {self.workspace_id}...")
        try:
            self.client.create_workspace(
                workspaceId=self.workspace_id,
                description="UR3 Robot Digital Twin Workspace",
                role=self.role_arn,
                s3Location=f"arn:aws:s3:::{self.s3_bucket}"
            )
            return self.wait_for_workspace_active()
        except Exception as e:
            print(f"Failed to create workspace: {e}")
            return False
    
    def wait_for_workspace_active(self, timeout: int = 1800) -> bool:
        """Wait for workspace to become active"""
        elapsed = 0
        while elapsed < timeout:
            try:
                response = self.client.get_workspace(workspaceId=self.workspace_id)
                state = response.get('state', 'UNKNOWN')
                print(f"Workspace state: {state} (elapsed: {elapsed}s)")
                
                if state == 'ACTIVE':
                    print("Workspace is ACTIVE!")
                    return True
                elif state == 'ERROR':
                    print(f"Workspace entered ERROR state: {response}")
                    return False
                    
            except ClientError as e:
                print(f"Error checking workspace: {e}")
                return False
            
            time.sleep(60)
            elapsed += 60
        
        print(f"Timeout waiting for workspace to become active")
        return False
    
    def create_component_type(self) -> bool:
        """Create component type for robot telemetry"""
        component_type_id = "com.ur3.robot.telemetry"
        
        try:
            self.client.get_component_type(
                workspaceId=self.workspace_id,
                componentTypeId=component_type_id
            )
            print(f"Component type {component_type_id} already exists")
            return True
        except ClientError as e:
            if e.response['Error']['Code'] != 'ResourceNotFoundException':
                raise
        
        component_def = {
            "description": "UR3 Robot Telemetry Component with Data Connector",
            "isSingleton": True,
            "functions": {
                "dataReader": {
                    "implementedBy": {
                        "lambda": {
                            "arn": self.lambda_arn
                        }
                    },
                    "isInherited": False,
                    "scope": "ENTITY"
                }
            },
            "propertyDefinitions": self._get_property_definitions()
        }
        
        try:
            self.client.create_component_type(
                workspaceId=self.workspace_id,
                componentTypeId=component_type_id,
                **component_def
            )
            print(f"Created component type {component_type_id}")
            time.sleep(15)
            return True
        except Exception as e:
            print(f"Failed to create component type: {e}")
            return False
    
    def _get_property_definitions(self) -> Dict[str, Any]:
        """Define properties for the component type"""
        joint_properties = {}
        for i in range(1, 4):
            joint_properties[f"joint{i}_position"] = {
                "dataType": {"type": "DOUBLE"},
                "isTimeSeries": True,
                "isStoredExternally": True,
                "defaultValue": {"doubleValue": 0.0},
                "isRequiredInEntity": False
            }
            joint_properties[f"joint{i}_target"] = {
                "dataType": {"type": "DOUBLE"},
                "isTimeSeries": False,
                "isStoredExternally": False,
                "defaultValue": {"doubleValue": 0.0},
                "isRequiredInEntity": False
            }
        
        joint_properties["robot_status"] = {
            "dataType": {"type": "STRING"},
            "isTimeSeries": True,
            "isStoredExternally": True,
            "defaultValue": {"stringValue": "IDLE"},
            "isRequiredInEntity": False
        }
        
        return joint_properties
    
    def create_entity(self) -> bool:
        """Create entity for the robot"""
        try:
            self.client.get_entity(
                workspaceId=self.workspace_id,
                entityId=self.entity_id
            )
            print(f"Entity {self.entity_id} already exists")
            return True
        except ClientError as e:
            if e.response['Error']['Code'] != 'ResourceNotFoundException':
                raise
        
        entity_def = {
            "entityName": "UR3 Robot 001",
            "description": "UR3 Robot Digital Twin Entity",
            "components": {
                "ur3_telemetry": {
                    "componentTypeId": "com.ur3.robot.telemetry",
                    "properties": self._get_initial_properties()
                }
            }
        }
        
        try:
            self.client.create_entity(
                workspaceId=self.workspace_id,
                entityId=self.entity_id,
                **entity_def
            )
            print(f"Created entity {self.entity_id}")
            time.sleep(10)
            return True
        except Exception as e:
            print(f"Failed to create entity: {e}")
            return False
    
    def _get_initial_properties(self) -> Dict[str, Any]:
        """Get initial property values for entity"""
        properties = {}
        for i in range(1, 4):
            properties[f"joint{i}_position"] = {"value": {"doubleValue": 0.0}}
            properties[f"joint{i}_target"] = {"value": {"doubleValue": 0.0}}
        properties["robot_status"] = {"value": {"stringValue": "IDLE"}}
        return properties
    
    def create_scene(self) -> bool:
        """Create 3D scene"""
        try:
            self.client.get_scene(
                workspaceId=self.workspace_id,
                sceneId=self.scene_id
            )
            print(f"Scene {self.scene_id} already exists")
            return True
        except ClientError as e:
            if e.response['Error']['Code'] != 'ResourceNotFoundException':
                raise
        
        # Upload scene content to S3
        scene_content = {
            "version": "1.0",
            "unit": "meters",
            "nodes": [
                {
                    "name": "UR3_Robot_001",
                    "transform": {
                        "position": [0, 0, 0],
                        "rotation": [0, 0, 0],
                        "scale": [1, 1, 1]
                    },
                    "properties": {
                        "entityId": self.entity_id,
                        "componentName": "ur3_telemetry"
                    },
                    "children": []
                }
            ],
            "rootNodeIndexes": [0]
        }
        
        scene_key = f"scenes/{self.scene_id}.json"
        try:
            self.s3_client.put_object(
                Bucket=self.s3_bucket,
                Key=scene_key,
                Body=json.dumps(scene_content),
                ContentType='application/json'
            )
            print(f"Uploaded scene content to S3")
        except Exception as e:
            print(f"Failed to upload scene content: {e}")
            return False
        
        try:
            self.client.create_scene(
                workspaceId=self.workspace_id,
                sceneId=self.scene_id,
                contentLocation=f"arn:aws:s3:::{self.s3_bucket}/{scene_key}",
                description="UR3 Robot 3D Scene"
            )
            print(f"Created scene {self.scene_id}")
            return True
        except Exception as e:
            print(f"Failed to create scene: {e}")
            return False
    
    def setup_all(self) -> bool:
        """Run complete setup"""
        steps = [
            ("Workspace", self.create_workspace),
            ("Component Type", self.create_component_type),
            ("Entity", self.create_entity),
            ("Scene", self.create_scene)
        ]
        
        for name, func in steps:
            print(f"\n{'='*60}")
            print(f"Setting up {name}...")
            print('='*60)
            if not func():
                print(f"Failed to setup {name}")
                return False
        
        print("\n" + "="*60)
        print("TwinMaker setup completed successfully!")
        print("="*60)
        return True
    
    def cleanup(self) -> bool:
        """Clean up all TwinMaker resources"""
        print("Cleaning up TwinMaker resources...")
        
        cleanup_steps = [
            ("Entity", lambda: self.client.delete_entity(
                workspaceId=self.workspace_id, entityId=self.entity_id)),
            ("Component Type", lambda: self.client.delete_component_type(
                workspaceId=self.workspace_id, componentTypeId="com.ur3.robot.telemetry")),
            ("Scene", lambda: self.client.delete_scene(
                workspaceId=self.workspace_id, sceneId=self.scene_id)),
            ("Workspace", lambda: self.client.delete_workspace(
                workspaceId=self.workspace_id))
        ]
        
        for name, func in cleanup_steps:
            try:
                func()
                print(f"Deleted {name}")
                time.sleep(10)
            except ClientError as e:
                if e.response['Error']['Code'] != 'ResourceNotFoundException':
                    print(f"Error deleting {name}: {e}")
        
        print("Cleanup completed")
        return True


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='Setup TwinMaker resources')
    parser.add_argument('--region', required=True, help='AWS region')
    parser.add_argument('--workspace-id', required=True, help='Workspace ID')
    parser.add_argument('--entity-id', required=True, help='Entity ID')
    parser.add_argument('--scene-id', required=True, help='Scene ID')
    parser.add_argument('--role-arn', required=True, help='IAM role ARN')
    parser.add_argument('--s3-bucket', required=True, help='S3 bucket name')
    parser.add_argument('--lambda-arn', required=True, help='Lambda function ARN')
    parser.add_argument('--cleanup', action='store_true', help='Cleanup resources')
    
    args = parser.parse_args()
    
    setup = TwinMakerSetup(
        region=args.region,
        workspace_id=args.workspace_id,
        entity_id=args.entity_id,
        scene_id=args.scene_id,
        role_arn=args.role_arn,
        s3_bucket=args.s3_bucket,
        lambda_arn=args.lambda_arn
    )
    
    if args.cleanup:
        success = setup.cleanup()
    else:
        success = setup.setup_all()
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()