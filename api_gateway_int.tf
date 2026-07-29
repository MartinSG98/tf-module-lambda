resource "aws_apigatewayv2_integration" "integration" {
  count = (var.api_gateway_id != null) ? 1 : 0

  api_id                 = var.api_gateway_id
  description            = "Integration with ${var.name_prefix} function"
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.lambda_function.invoke_arn
  payload_format_version = "2.0"
  region                 = var.region
}

resource "aws_lambda_permission" "invoke" {
  count = (var.api_gateway_id != null) ? 1 : 0

  statement_id  = "ApiGwInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_execution_arn}/*"
  region        = var.region
  lifecycle {
    replace_triggered_by = [aws_lambda_function.lambda_function]
  }
}
