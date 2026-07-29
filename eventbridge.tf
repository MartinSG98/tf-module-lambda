resource "aws_cloudwatch_event_rule" "schedule" {
  # An EventBridge rule can have a maximum of 5 targets. If we have more, we create multiple rules to assign them to
  count               = var.cron_expression == null ? 0 : (var.cron_invocation_inputs == null ? 1 : floor(length(var.cron_invocation_inputs) / 5) + 1)
  state               = var.cron_rule_enabled ? "ENABLED" : "DISABLED"
  name                = trim(substr("${var.name_prefix}_lambda_schedule_${count.index}-evbr-${module.helpers.name_suffix}", 0, 64), "-")
  schedule_expression = var.cron_expression
  region              = var.region
  tags                = local.tags
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  count         = var.cron_expression == null ? 0 : (var.cron_invocation_inputs == null ? 1 : floor(length(var.cron_invocation_inputs) / 5) + 1)
  statement_id  = "AllowExecutionFromEventBridge${count.index}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule[count.index].arn
  region        = var.region
  lifecycle {
    # If the function is replaced, this permission silently evaporates (this will cause replacements if *anything* changes, but there's no more targetted way to do it)
    replace_triggered_by = [aws_lambda_function.lambda_function]
  }
}

resource "aws_cloudwatch_event_target" "run_service" {
  count     = var.cron_expression == null ? 0 : (var.cron_invocation_inputs == null ? 1 : length(var.cron_invocation_inputs))
  target_id = "${var.name_prefix}${count.index}-evbt-${module.helpers.name_suffix}"
  rule      = aws_cloudwatch_event_rule.schedule[floor(count.index / 5)].name
  arn       = aws_lambda_function.lambda_function.arn
  input     = var.cron_invocation_inputs == null ? null : var.cron_invocation_inputs[count.index]
  region    = var.region
}
