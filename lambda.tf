# Lambda function creation
resource "aws_lambda_function" "lambda_function" {
  function_name = "${var.name_prefix}-fun-${module.helpers.name_suffix}"

  image_uri        = var.image_uri
  filename         = var.local_code_dir != null && var.s3_bucket == null ? data.archive_file.local_package[0].output_path : var.filename
  s3_bucket        = var.s3_bucket
  s3_key           = var.local_code_dir != null && var.s3_bucket != null ? aws_s3_object.package_upload[0].key : var.s3_key
  package_type     = var.image_uri == null ? "Zip" : "Image"
  source_code_hash = var.local_code_dir != null ? terraform_data.source_code_hash[0].output : (var.filename != null ? (var.source_code_hash != null ? var.source_code_hash : filebase64sha256(var.filename)) : null)
  region           = var.region

  role          = aws_iam_role.lambda-iam-role.arn
  runtime       = var.runtime
  handler       = var.handler
  timeout       = var.timeout
  memory_size   = var.memory_size_mb
  architectures = [var.architecture]
  publish       = var.is_lambda_at_edge # Lambda@Edge requires a specific version to be referenced

  layers = var.layers

  # Only create the environment block if needed - terraform shows a continual difference if it's unset (bug)
  dynamic "environment" {
    for_each = var.environment_vars == null ? [] : [1]
    content {
      variables = var.environment_vars
    }
  }

  # If subnet_ids, security_group_ids and ipv6_allowed_for_dual_stack are empty then vpc_config is considered to be unset
  vpc_config {
    subnet_ids         = coalesce(var.subnet_ids, [])
    security_group_ids = var.vpc_id == null ? [] : [aws_security_group.lambda_sg[0].id]
  }

  lifecycle {
    # If we have a security group and it needs to be replaced, the lambda must be removed so its EIPs can be disassociated from the SG
    replace_triggered_by = [terraform_data.lambda_has_sg]
    # NOTE: this is over-zealous - it replaces the function and related things on every minor change (e.g. tagging) - but it is necessary

    precondition {
      condition     = !var.is_lambda_at_edge || module.helpers.region_name == "us-east-1" || var.region == "us-east-1"
      error_message = "Lambda@Edge functions must be deployed in us-east-1."
    }
    precondition {
      condition     = !var.is_lambda_at_edge || var.architecture == "x86_64"
      error_message = "Lambda@Edge functions must use the x86_64 architecture."
    }
    precondition {
      condition     = !var.is_lambda_at_edge || var.environment_vars == null
      error_message = "Lambda@Edge functions cannot have environment variables."
    }
  }

  tags = merge(
    local.tags,
    var.image_update_on_push && (var.image_uri != null || var.s3_key != null) ? { UpdateOnEcrPush = "yes" } : {}
  )
}

# Intermediary resource between the security group and the lambda, because the SG does not have to exist.
# Approach taken from: https://discuss.hashicorp.com/t/replace-triggered-by-on-conditionally-created-resources/67079
resource "terraform_data" "lambda_has_sg" {
  input = try(aws_security_group.lambda_sg[0], null)
}

# Lambda Security Group
resource "aws_security_group" "lambda_sg" {
  count  = var.vpc_id == null ? 0 : 1
  name   = "${var.name_prefix}_lambda-sg-${module.helpers.name_suffix}"
  vpc_id = var.vpc_id
  region = var.region

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.tags,
    { Name = "${var.name_prefix}_lambda-sg-${module.helpers.name_suffix}" }
  )
}

# Lambda IAM role creation
resource "aws_iam_role" "lambda-iam-role" {
  name = trim(substr("${var.name_prefix}_iam-role-lambda-${module.helpers.name_suffix}", 0, 64), "-")
  assume_role_policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = ["sts:AssumeRole"]
          Principal = {
            Service = var.is_lambda_at_edge ? ["lambda.amazonaws.com", "edgelambda.amazonaws.com"] : ["lambda.amazonaws.com"]
          }
        }
      ]
    }
  )
}

# AWS issued policy for Lambda role
resource "aws_iam_role_policy_attachment" "att_pol_lambda" {
  role = aws_iam_role.lambda-iam-role.name
  policy_arn = (var.vpc_id == null ?
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  : "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole")
}

# Optional extra permissions if supplied
resource "aws_iam_policy" "policy_additional" {
  count  = var.iam_policy_additional == null ? 0 : 1
  name   = "${var.name_prefix}_iam-add-pol-lambda-${module.helpers.name_suffix}"
  policy = var.iam_policy_additional
}

resource "aws_iam_role_policy_attachment" "att_add_pol_lambda" {
  count      = var.iam_policy_additional == null ? 0 : 1
  role       = aws_iam_role.lambda-iam-role.name
  policy_arn = aws_iam_policy.policy_additional[0].arn
}

resource "random_id" "version" {
  byte_length = 2

  lifecycle {
    replace_triggered_by = [aws_lambda_function.lambda_function]
  }
  keepers = {
    lambda_code_hash = var.local_code_dir != null ? random_uuid.lambda_code_hash[0].id : null
  }
}
