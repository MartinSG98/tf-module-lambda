# Inputs into this module
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "environment" {
  type        = string
  description = "The name of the environment in which this module is being invoked"
  validation {
    condition     = contains(["sand", "dev", "uat", "perf", "stage", "prod", "core", "shared"], var.environment)
    error_message = "Environment must be one of sand, dev, uat, perf, stage, prod, core or shared."
  }
}

# Tags to add on to the default set on the provider
variable "tags" {
  type        = map(string)
  description = "Additional tags to be applied to all resources created by this module"
  default     = {}
}

# Used to build name of objects we create
variable "name_prefix" {
  type        = string
  description = "Used for naming all resources created"
  validation {
    # We limit the name prefix to 30 characters or less to prevent names getting too long for some services
    condition = (
      can(regex("^[a-z0-9_]+$", var.name_prefix)) && (length(var.name_prefix) <= 30)
    )
    error_message = "Name prefix must be numbers, lowercase letters and underscores, 30 characters maximum."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC in which to create resources"
  default     = null
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs to execute the lambda in"
  default     = null
}

variable "iam_policy_additional" {
  type        = string
  description = "Additional IAM policies to also attach to IAM role"
  default     = null
}

variable "cron_expression" {
  type        = string
  description = "Cron expression - optional use for function to be used alongside eventbridge."
  default     = null
}

variable "cron_invocation_inputs" {
  type        = list(string)
  description = "Payload to pass to lambda - if multiple payloads submitted, lambda will execute in parallel once per payload"
  default     = null
}

variable "cron_rule_enabled" {
  type        = bool
  description = "Whether to enable the rule created by cron_expression"
  default     = true
}

variable "error_pattern" {
  type        = string
  description = "A pattern which when found in the log group will produce an alarm"
  default     = null
}

variable "timeout" {
  type        = number
  description = "The lambda timeout in seconds"
}

variable "memory_size_mb" {
  type        = number
  description = "The lambda memory size in megabytes"
  default     = 128
}

variable "environment_vars" {
  type        = map(string)
  description = "Variables that the executing function can use"
  default     = null
}

variable "filename" {
  type        = string
  description = "Deployment package (zip) as a local file"
  default     = null
}

variable "source_code_hash" {
  type        = string
  description = "Base64-encoded SHA256 hash of the zip file"
  default     = null
}

variable "s3_bucket" {
  type        = string
  description = "S3 bucket location"
  default     = null
}

variable "s3_key" {
  type        = string
  description = "S3 key of the object containing deployment package"
  default     = null
}

variable "image_uri" {
  type        = string
  description = "ECR image URI containing the function's deployment package"
  default     = null
}

variable "local_code_dir" {
  type        = string
  description = "Local directory containing the function's deployment code, to be packaged and deployed"
  default     = null
  validation {
    condition = (
      var.local_code_dir == null || can(regex("^.*[^/]$", var.local_code_dir))
    )
    error_message = "No trailing slash on the directory name."
  }
}

variable "runtime" {
  type        = string
  description = "Lambda runtime to use - required for all types except image_uri"
  default     = null
}

variable "handler" {
  type        = string
  description = "Entry point in function - required for all types except image_uri"
  default     = null
}

variable "image_update_on_push" {
  type        = string
  description = "Automatically update the lambda when a new image is pushed to the repo"
  default     = false
}

variable "architecture" {
  type        = string
  description = "Execution architecture"
  default     = "x86_64"
  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "Architecture must be either x86_64 or arm64."
  }
}

variable "is_lambda_at_edge" {
  type        = bool
  description = "Whether this is being used as a Lambda@Edge function"
  default     = false
}

variable "api_gateway_id" {
  type        = string
  description = "API gateway identifier"
  default     = null
  validation {
    condition = (
      (var.api_gateway_id == null && var.api_gateway_execution_arn == null) ||
      (var.api_gateway_id != null && var.api_gateway_execution_arn != null)
    )
    error_message = "api_gateway_id and api_gateway_execution_arn must either both be set or both be null."
  }
}

variable "api_gateway_execution_arn" {
  type        = string
  description = "Gateway ARN prefix to be used in an aws_lambda_permission's source_arn attribute or in an aws_iam_policy to authorize access to the @connections API."
  default     = null
}

variable "region" {
  type        = string
  description = "This is the region in which the function will be created, if different to the default region on the provider."
  default     = null
}

variable "layers" {
  type        = list(string)
  description = "List of Lambda layer ARNs to attach to the function"
  default     = []
}

variable "account_shortname" {
  type        = string
  description = "Optional short name for the current account, used in resource name suffixes. Falls back to the raw account ID when not set."
  default     = null
}
