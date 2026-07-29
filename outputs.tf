# Lambda Security Group id
output "security_group_id" {
  value = (var.vpc_id == null ? null : aws_security_group.lambda_sg[0].id)
}

output "lambda_function_arn" {
  value = aws_lambda_function.lambda_function.arn
}

output "lambda_function_qualified_arn" {
  value = aws_lambda_function.lambda_function.qualified_arn
}

output "lambda_function_name" {
  value = aws_lambda_function.lambda_function.function_name
}

output "lambda_function_unique_id" {
  value = random_id.version.hex
}

output "lambda_function_invoke_arn" {
  value = aws_lambda_function.lambda_function.invoke_arn
}

output "lambda_iam_role_name" {
  value = aws_iam_role.lambda-iam-role.name
}

output "api_gateway_integration_id" {
  value = var.api_gateway_id != null ? aws_apigatewayv2_integration.integration[0].id : null
}
