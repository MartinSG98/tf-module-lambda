# The actual lambda to do the force-redeploy must already exist in the account
# (created once per account/environment by your deployment environment stack)
data "aws_lambda_function" "image_update" {
  count         = var.image_update_on_push && (var.image_uri != null || (var.s3_bucket != null && var.s3_key != null)) ? 1 : 0
  function_name = "lambda_image_updater-fun-${module.helpers.name_suffix}" # TODO: this could need a name_prefix in future
  region        = var.region
}

# Provides EventBridge with the permission to trigger the image update lambda when image pushed
# NOTE: this will silently evaporate if the function is ever replaced
resource "aws_lambda_permission" "allow_cloudwatch_exec" {
  count         = var.image_update_on_push && var.image_uri != null ? 1 : 0
  statement_id  = "${var.name_prefix}_AllowExecutionFromEventbridge"
  action        = "lambda:InvokeFunction"
  function_name = data.aws_lambda_function.image_update[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.image_pushed[0].arn
  region        = var.region
}

# Provides EventBridge with the permission to trigger the image update lambda when S3 changes
# NOTE: point above for "allow_cloudwatch_exec"
resource "aws_lambda_permission" "allow_s3_cloudwatch_exec" {
  count         = var.image_update_on_push && var.s3_bucket != null && var.s3_key != null ? 1 : 0
  statement_id  = "${var.name_prefix}_AllowExecutionFromEventbridge"
  action        = "lambda:InvokeFunction"
  function_name = data.aws_lambda_function.image_update[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.s3_changed[0].arn
  region        = var.region
}

# EventBridge rule that triggers the image update lambda
resource "aws_cloudwatch_event_rule" "image_pushed" {
  count       = var.image_update_on_push && var.image_uri != null ? 1 : 0
  name        = "${var.name_prefix}_image_update-evbr-${module.helpers.name_suffix}"
  description = "New image pushed to ${var.name_prefix} lambda's ECR repo"
  region      = var.region

  event_pattern = jsonencode({
    source      = ["aws.ecr"],
    detail-type = ["ECR Image Action"],
    detail = {
      result          = ["SUCCESS"]
      repository-name = [split(":", split("/", var.image_uri)[1])[0]],
      action-type     = ["PUSH"]
      image-tag       = [split(":", var.image_uri)[1]]
    }
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "deploy" {
  count     = var.image_update_on_push && var.image_uri != null ? 1 : 0
  target_id = "${var.name_prefix}_deploy_lambda-evbt-${module.helpers.name_suffix}"
  rule      = aws_cloudwatch_event_rule.image_pushed[0].name
  arn       = data.aws_lambda_function.image_update[0].arn
  input     = jsonencode({ "function-name" = aws_lambda_function.lambda_function.function_name, "image-uri" = var.image_uri })
  region    = var.region
}

# EventBridge rule that triggers the S3 update lambda
resource "aws_cloudwatch_event_rule" "s3_changed" {
  count       = var.image_update_on_push && var.s3_bucket != null && var.s3_key != null ? 1 : 0
  name        = "${var.name_prefix}_s3_update-evbr-${module.helpers.name_suffix}"
  description = "New S3 zip available for ${var.name_prefix} lambda upload bucket"
  region      = var.region

  event_pattern = jsonencode({
    source      = ["aws.s3"],
    detail-type = ["Object Created"],
    detail = {
      bucket = {
        name = [var.s3_bucket]
      },
      object = {
        key = [var.s3_key]
      }
    }
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "s3_deploy" {
  count     = var.image_update_on_push && var.s3_bucket != null && var.s3_key != null ? 1 : 0
  target_id = "${var.name_prefix}_s3_deploy_lambda-evbt-${module.helpers.name_suffix}"
  rule      = aws_cloudwatch_event_rule.s3_changed[0].name
  arn       = data.aws_lambda_function.image_update[0].arn
  input     = jsonencode({ "function-name" = aws_lambda_function.lambda_function.function_name, "s3-bucket" = var.s3_bucket, "s3-key" = var.s3_key })
  region    = var.region
}
