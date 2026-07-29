# Alarm if we match a pattern
resource "aws_cloudwatch_metric_alarm" "metric_alarm_pattern" {
  alarm_name          = "${var.name_prefix}_pattern-cwa-${module.helpers.name_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.log_metric_filter[0].name
  datapoints_to_alarm = 1
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Error pattern '${var.error_pattern}' found in logs from ${aws_lambda_function.lambda_function.function_name} (log group: ${aws_cloudwatch_log_group.lambda_log_group.name})"
  treat_missing_data  = "notBreaching"
  namespace           = "LambdaErrorCount"
  alarm_actions       = [module.helpers.sns_topic_arns["infracrit"]]
  ok_actions          = [module.helpers.sns_topic_arns["infracrit"]]
  region              = var.region

  tags = local.tags

  count = var.error_pattern == null ? 0 : 1
}

resource "aws_cloudwatch_log_metric_filter" "log_metric_filter" {
  name           = "${var.name_prefix}-cwm-${module.helpers.name_suffix}"
  pattern        = var.error_pattern
  log_group_name = aws_cloudwatch_log_group.lambda_log_group.name
  region         = var.region

  metric_transformation {
    name      = "ErrorCount"
    namespace = "LambdaErrorCount"
    value     = "1"
  }

  count = var.error_pattern == null ? 0 : 1
}

# Alarm if we exceed n% of the timeout
# Duration metric is the amount of time in milliseconds that the function spends processing an event
resource "aws_cloudwatch_metric_alarm" "metric_alarm_duration" {
  alarm_name          = "${var.name_prefix}_duration-cwa-${module.helpers.name_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Duration"
  datapoints_to_alarm = 1
  period              = 60
  statistic           = "Maximum"
  threshold           = var.timeout * 1000 * 0.90 # Convert to milli-seconds and take 90 % of that
  alarm_description   = "${aws_lambda_function.lambda_function.function_name} has exceeded threshold duration of ${var.timeout * 0.90} seconds"
  treat_missing_data  = "notBreaching"
  namespace           = "AWS/Lambda"
  alarm_actions       = [module.helpers.sns_topic_arns["infrawarn"]]
  ok_actions          = [module.helpers.sns_topic_arns["infrawarn"]]
  region              = var.region

  dimensions = {
    FunctionName = "${aws_lambda_function.lambda_function.function_name}"
  }

  tags = local.tags
}

# Alarm if a single execution has errored in period
resource "aws_cloudwatch_metric_alarm" "metric_alarm_error_rate" {
  alarm_name          = "${var.name_prefix}_error_rate-cwa-${module.helpers.name_suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  alarm_description   = "There has been an error for ${aws_lambda_function.lambda_function.function_name}"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [module.helpers.sns_topic_arns["infracrit"]]
  ok_actions          = [module.helpers.sns_topic_arns["infracrit"]]
  region              = var.region

  metric_name = "Errors"
  namespace   = "AWS/Lambda"
  period      = 300 # 5 minutes
  statistic   = "Sum"

  dimensions = {
    FunctionName = "${aws_lambda_function.lambda_function.function_name}"
  }

  tags = local.tags
}

# Alarm if execution has been throttled.
resource "aws_cloudwatch_metric_alarm" "metric_alarm_throttle_rate" {
  alarm_name          = "${var.name_prefix}_throttle_rate-cwa-${module.helpers.name_suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  alarm_description   = "1 or more executions of ${aws_lambda_function.lambda_function.function_name} has been throttled"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [module.helpers.sns_topic_arns["infrawarn"]]
  ok_actions          = [module.helpers.sns_topic_arns["infrawarn"]]
  region              = var.region

  metric_name = "Throttles"
  namespace   = "AWS/Lambda"
  period      = 300
  statistic   = "Sum"

  dimensions = {
    FunctionName = "${aws_lambda_function.lambda_function.function_name}"
  }

  tags = local.tags
}

# Cloudwatch Log group creation
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.lambda_function.function_name}"
  retention_in_days = (var.environment == "prod") ? 365 : 14 # Standard policy: 365 days in prod, 14 days elsewhere
  region            = var.region

  tags = merge(
    local.tags,
    { DataClassification = "Internal data" }
  )
}
