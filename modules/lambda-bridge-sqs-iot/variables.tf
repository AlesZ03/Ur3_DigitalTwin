

variable "bridge_function_name" {
  description = "A híd Lambda függvény neve"
  type        = string
  default     = "sqs-to-iot-bridge-lambda"
}

variable "sqs_queue_arn" {
  description = "A meglévő SQS sor ARN-je, amiből a Lambda olvasni fog"
  type        = string
}

variable "iot_endpoint" {
  description = "Az AWS IoT Core ATS végpontja (idézőjelek és https:// nélkül, pl. xxxx-ats.iot.eu-central-1.amazonaws.com)"
  type        = string
}

variable "iot_topic" {
  description = "Az MQTT topik neve, ahova a robot parancsait küldjük"
  type        = string
  default     = "ur3/commands"
}

variable "bridge_lambda_source_file_path" {
  description = "Az index.py fájl helye a gépeden (pl. ./src/bridge/index.py)"
  type        = string
}

variable "bridge_lambda_output_zip_path" {
  description = "Hova generálja a ZIP fájlt (pl. ./src/bridge/lambda.zip)"
  type        = string
}