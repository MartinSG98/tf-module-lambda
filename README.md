# tf-module-lambda

Creates a Lambda function with everything that usually goes around it: an IAM role, a log group, alarms, and optionally a security group in a VPC, an EventBridge schedule, an HTTP API integration and automatic redeploys when a new image or zip is pushed. The code can come from four kinds of source (see "Deployment types" below), one of which is a local directory that the module packages for you. It also works as a Lambda@Edge function, which is how [tf-module-cloudfront](https://github.com/MartinSG98/tf-module-cloudfront) builds its IP allow list.

The function is named `<name_prefix>-fun-<suffix>`, with the name suffix from [tf-module-helpers](https://github.com/MartinSG98/tf-module-helpers). The module needs Terraform 1.9 or newer, because one input validation refers to another input, the AWS provider 6.x, and the hashicorp/random and hashicorp/archive providers.

```hcl
module "ping" {
  source = "git::https://github.com/MartinSG98/tf-module-lambda.git?ref=1.0.0"

  environment    = var.environment
  name_prefix    = "myapp_ping"
  local_code_dir = "${path.module}/functions/ping"
  runtime        = "python3.13"
  handler        = "main.lambda_handler"
  architecture   = "arm64"
  timeout        = 10

  environment_vars = {
    LOG_LEVEL = "INFO"
  }

  tags = local.tags
}
```

## What it creates

- **The IAM role** `<name_prefix>_iam-role-lambda-<suffix>` (cut to 64 characters) has `AWSLambdaBasicExecutionRole`, or `AWSLambdaVPCAccessExecutionRole` when the function runs in a VPC. `iam_policy_additional` adds a customer-managed policy with extra permissions.
- **The log group** `/aws/lambda/<function name>` keeps logs for 365 days in `prod` and 14 days elsewhere.
- **Alarms** fire when an invocation runs longer than 90 percent of `timeout`, when any invocation errors or is throttled within five minutes, and, if you set `error_pattern`, when that pattern shows up in the logs. Errors and the error pattern notify the `infracrit` topic, duration and throttles the `infrawarn` topic, both from tf-module-helpers.
- **A security group**, when `vpc_id` is set, with all outbound traffic allowed and no inbound rules. The function runs in `subnet_ids`. A `terraform_data` resource (`lambda_has_sg`) sits between the security group and the function, so the function's `replace_triggered_by` works whether or not there is a security group. Any change to the security group, even a tag, replaces the function.
- **A schedule**, when `cron_expression` is set ([syntax](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-cron-expressions.html)). With `cron_invocation_inputs` the function runs once per payload, in parallel. An EventBridge rule takes at most five targets, so more payloads are spread over several rules. `cron_rule_enabled = false` creates the rules switched off.
- **An HTTP API integration**, when `api_gateway_id` and `api_gateway_execution_arn` are set. It is an `AWS_PROXY` integration with payload format 2.0, plus permission for that API to invoke the function. The route is yours to create, with `integrations/<api_gateway_integration_id>` as its target. [tf-module-api_gateway](https://github.com/MartinSG98/tf-module-api_gateway) shows an example.

## Lambda@Edge

Set `is_lambda_at_edge = true` for a function that CloudFront runs. The module then publishes a version on every change and lets `edgelambda.amazonaws.com` assume the role as well. Preconditions check that the function is in `us-east-1` (through the provider's region or `region`), uses `x86_64` and has no environment variables. Associate `lambda_function_qualified_arn` with the distribution. Deleting a function that has been used at the edge can be [slow and painful](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/lambda-edge-delete-replicas.html).

## Permissions that disappear

When a function is replaced, any `aws_lambda_permission` attached to it silently disappears, and it takes a second `terraform apply` to put it back. The module's own permissions (for the schedule and the HTTP API) are replaced along with the function. For your own permissions, use `lambda_function_unique_id`, which changes whenever the function is updated or replaced, to trigger their replacement through a [`terraform_data`](https://developer.hashicorp.com/terraform/language/resources/terraform-data#example-usage-data-for-replace_triggered_by) resource.

## Deployment types

The code comes from one of four sources: `image_uri`, `filename`, `s3_bucket` with `s3_key`, or `local_code_dir`. Give one of them. `local_code_dir` can be combined with `s3_bucket` to upload the package through S3. `runtime` and `handler` are needed for every type except `image_uri`.

### `image_uri`, a container image in ECR

The function runs the given container image.

### `filename`, a zip file on disk

The code is a zip file at the given local path. A zip uploaded directly [may not exceed 50 MB](https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html#function-configuration-deployment-and-execution), so use another type for anything bigger.

`source_code_hash` is the base64-encoded SHA256 hash of the zip, so that the function is updated whenever the zip changes. If you build the zip with an `archive_file`, pass its [`output_base64sha256`](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/resources/file#output_base64sha256-1) attribute. If you leave it out, the module works it out with `filebase64sha256(filename)`.

### `s3_bucket` and `s3_key`, a zip file in S3

The code is a zip file in the given bucket, which has to be in the same region as the function. `s3_key` is the object key without a leading slash, for example `"folder/file.zip"`.

Do not upload this zip with Terraform's `aws_s3_object`. If something else replaces the zip later, Terraform puts the original back on every apply.

### `local_code_dir`, built from a local directory

The module packages the directory for you and uploads it, through S3 if `s3_bucket` is set and directly otherwise (with the 50 MB limit above). The path takes no trailing slash. When you call this module from inside another module, which is the usual case, prefix the path with `${path.module}/`.

The zip goes into `.lambda_build_cache/` in the root of the stack, named after the function and a random ID that changes whenever a file in the directory changes. The files there are temporary, so add the directory to your `.gitignore`. Older zips of the same function are deleted with `find`, which may not work on Windows. The first clean-up fails if the directory does not exist yet, so apply again if you see `./.lambda_build_cache: No such file or directory`. The package hash is kept stable across machines, so building the same code on another engineer's machine does not cause a change.

If the directory has a `requirements.txt`, the module runs `pip install -r <dir>/requirements.txt -t <dir>/` whenever that file changes, so `pip` has to be installed where Terraform runs. You do not need to install anything the runtime already includes. "Provider produced inconsistent final plan" can appear after you change `requirements.txt`. Run `terraform apply` again and it goes through.

Because the package is built locally, any libraries are downloaded for your machine's operating system and CPU, which may not match Lambda's. Only use libraries written in pure Python, with no OS-specific binary parts. The build also runs no tests before it deploys, so this type suits small, simple functions. For anything more, use one of the other types with a pipeline that builds, tests and delivers the code.

New dependencies are picked up automatically, but anything you remove from `requirements.txt` has to be cleaned out of the directory by hand. Update libraries now and then for bug and security fixes with `pip install -r requirements.txt -t . --upgrade` in the directory, and test afterwards. Check the library files into git along with the code. `pip` only runs when `requirements.txt` changes, so a fresh checkout without them would build a package that is missing its libraries.

## Automatic redeploys

`image_update_on_push = true` redeploys the function when its code changes outside Terraform. It relies on an updater function named `lambda_image_updater-fun-<suffix>`, which has to exist in the account already (one per account and environment, created by your environment stack). It is not part of this module.

- **With `image_uri`**, an EventBridge rule watches for a successful push to the image's ECR repository with the image's tag, and calls the updater with the function name and the image URI. The URI must include a tag. This is what you want with a tag such as `:latest` that moves, rather than a fixed version tag.
- **With `s3_bucket` and `s3_key`**, a rule watches for a new object at that key and calls the updater with the function name, bucket and key. The bucket has to send its events to EventBridge. In the setup this module came from, the updater also backs up the previous zip next to the new one. For example, with `s3_key = "myapp/ping.zip"` the old zip goes to `myapp/ping/2025-03-31-22-36-06.zip` in the same bucket.

The function also gets an `UpdateOnEcrPush = yes` tag.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `environment` | `string` | required | Environment the module is used in: `sand`, `dev`, `uat`, `perf`, `stage`, `prod`, `core` or `shared` |
| `name_prefix` | `string` | required | Prefix for all resource names, in lower-case letters, digits and underscores, 30 characters at most |
| `timeout` | `number` | required | Longest time in seconds the function may run. The duration alarm fires at 90 percent of it |
| `runtime` | `string` | `null` | [Runtime](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html), for example `python3.13`. Needed for every type except `image_uri` |
| `handler` | `string` | `null` | Entry point, as module and function. For `lambda_handler()` in `main.py` this is `main.lambda_handler`. Needed for every type except `image_uri` |
| `image_uri` | `string` | `null` | ECR image URI with the function's code |
| `filename` | `string` | `null` | Path to a local zip with the function's code |
| `source_code_hash` | `string` | `null` | Base64-encoded SHA256 hash of `filename`. Worked out from the file when left out |
| `s3_bucket` | `string` | `null` | Bucket holding the zip, or the bucket to upload a `local_code_dir` package to |
| `s3_key` | `string` | `null` | Key of the zip in `s3_bucket` |
| `local_code_dir` | `string` | `null` | Local directory to package and deploy, without a trailing slash |
| `memory_size_mb` | `number` | `128` | Memory in MB |
| `architecture` | `string` | `"x86_64"` | `x86_64` or `arm64`. Use `arm64` wherever you can, it is about [20 percent cheaper](https://aws.amazon.com/lambda/pricing/) |
| `environment_vars` | `map(string)` | `null` | Environment variables for the function |
| `layers` | `list(string)` | `[]` | Lambda layer ARNs to attach |
| `vpc_id` | `string` | `null` | VPC to create the function's security group in. Leave it out unless the function needs to reach resources inside a VPC |
| `subnet_ids` | `list(string)` | `null` | Subnets, in `vpc_id`, to run the function in |
| `iam_policy_additional` | `string` | `null` | JSON policy document with extra permissions for the function's role |
| `error_pattern` | `string` | `null` | Log pattern that raises an alarm when it appears |
| `cron_expression` | `string` | `null` | Schedule for running the function through EventBridge |
| `cron_invocation_inputs` | `list(string)` | `null` | Payloads (for example JSON) for scheduled runs, one invocation per payload |
| `cron_rule_enabled` | `bool` | `true` | Whether the schedule's rules are enabled |
| `image_update_on_push` | `string` | `false` | Redeploy when a new image is pushed to `image_uri` or a new zip lands at `s3_bucket` and `s3_key`. Declared as a string but used as a boolean, so pass `true` or `false` |
| `is_lambda_at_edge` | `bool` | `false` | Whether this is a Lambda@Edge function for CloudFront |
| `api_gateway_id` | `string` | `null` | HTTP API to integrate with. Set together with `api_gateway_execution_arn` or not at all |
| `api_gateway_execution_arn` | `string` | `null` | Execution ARN of that API, used as the `source_arn` of the invoke permission |
| `region` | `string` | `null` | Region for the function and everything around it, if different from the provider's default region. It takes precedence over the provider's region |
| `account_shortname` | `string` | `null` | Short name for the current account in name suffixes. Falls back to the account ID |
| `tags` | `map(string)` | `{}` | Extra tags for the resources. An `InfraModule` tag is added with `tf-module-lambda`, followed by any `InfraModule` value you pass here |

## Outputs

| Name | Description |
|---|---|
| `lambda_function_name` | Name of the function |
| `lambda_function_arn` | ARN of the function |
| `lambda_function_qualified_arn` | ARN of the function including its version, which Lambda@Edge needs |
| `lambda_function_invoke_arn` | ARN API Gateway uses to invoke the function |
| `lambda_function_unique_id` | Random ID that changes whenever the function is updated or replaced, for triggering the replacement of your own `aws_lambda_permission` resources |
| `lambda_iam_role_name` | Name of the function's IAM role, for attaching more policies |
| `security_group_id` | ID of the function's security group, or null without `vpc_id` |
| `api_gateway_integration_id` | ID of the HTTP API integration, for the `target` of an `aws_apigatewayv2_route`, or null without `api_gateway_id` |
