# tf-module-lambda

This module creates resources for implementing a generic lambda function. It supports various deployment types.

## Inputs

* `name_prefix`: The first part of the name for all resources created.
* `vpc_id`: The VPC hosting the lambda function (if required). If the lambda does not need direct access to non-default VPC resources we do not need to pass it one. We use a terraform_data resource, lambda_has_sg, an an intermediary resource between the security group and the lambda so the lambda's lifecycle Meta-Argument will work both when we have a lambda and when we do not.
* `subnet_ids`: Optional list of subnets in which to execute the lambda function (within the given vpc_id VPC).
* `image_uri`, `filename`, `source_code_hash`, `s3_bucket`, `s3_key` and `local_code_dir`: The location of the lambda code (see "Deployment types" below).
* `runtime`: The [programming language release](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html) with which to execute your code.
* `handler`: The entry point (module and function name) into the code. For example, if your entrypoint function is `lambda_handler()` in main.py, this would be "main.lambda_handler".
* `environment_vars`: Environment variables that the executing function can use.
* `memory_size_mb`: Memory to allocate, in MB (defaults to 128MB).
* `architecture`: The runtime architecture - x86_64 is the default, but arm64 should be used wherever possible as it is [20% cheaper](https://aws.amazon.com/lambda/pricing/).
* `timeout`: Max time in seconds that the function may run before being timed out - must be explicitly given. An alarm will warn if an execution exceeds 90% of this.
* `iam_policy_additional`: Optional IAM policy specification, to grant extra permissions to the function (core permissions from [AWSLambdaVPCAccessExecutionRole](https://console.aws.amazon.com/iam/home#policies/arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole) are always included).
* `error_pattern`: Optional pattern to look for in the log output, which will produce an alarm if seen.
* `image_update_on_push`: Automatically update the lambda when a new image is pushed to `image_uri` (in ECR) **or** a new zip is available in `s3_bucket`+`s3_key`. For `image_uri` use you probably want this if using a `:latest` image which may change, rather than a specific version tag.
* `cron_expression`: Schedule regular executions of the lambda via EventBridge - see [syntax](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-cron-expressions.html).
* `cron_invocation_inputs`: Payload(s) (e.g. JSON) to pass to the function when executing as scheduled (one invocation per payload in the list).
* `cron_rule_enabled`: Whether to enable the EventBridge rule for `cron_expression` (enabled by default).
* `is_lambda_at_edge`: Whether this is a Lambda@Edge function (for CloudFront). There are two ways in which the precondition within the lifecycle block can be met. If the `module.helpers.region_name` or the variable `region` = us-east-1. You will need the `lambda_function_qualified_arn`: output to associate with the CloudFront distribution. Note that deleting a lambda which has been used for Lambda@Edge may be [slow and painful](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/lambda-edge-delete-replicas.html).
* `api_gateway_execution_arn`: If required - gateway ARN prefix to be used in an `aws_lambda_permission`'s `source_arn` attribute to authorize access to an API gateway.
* `region`: This is the region in which the function will be created, if different to the default region on the provider. The region of a resource can now be set via the provider of the resource or via `var.region` but the region variable will always take precedence.
* `layers`: Optional list of Lambda layer ARNs to attach to the function.


## Outputs

* `security_group_id` : The security group for the Lambda function.
* `lambda_function_arn` : The ARN of the lambda function created.
* `lambda_function_qualified_arn`: The qualified ARN (with version) of the lambda function created.
* `lambda_function_name` : The name of the Lambda function created.
* `lambda_function_unique_id` : A random identifier for this version of the function. Use this as to trigger, via a [`terraform_data`](https://developer.hashicorp.com/terraform/language/resources/terraform-data#example-usage-data-for-replace_triggered_by), replacement of any [`aws_lambda_permission`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) you associate with the function (if you don't, any changes to the function will cause the permission to silently evaporate, requiring a second `terraform apply` to restore)
* `lambda_function_invoke_arn` : The ARN used by the API Gateway for invocation.
* `lambda_iam_role_name` : The IAM Role Name used to attach managed policies.
* `api_gateway_integration_id` : The integration identifier that can be used from the passed `api_gateway_execution_arn`. This identifier can be put into the `target` of a `aws_apigatewayv2_route` resource which must be defined by the client using this module.

# Deployment types

This module can deploy code from four different source types as specified by the inputs `image_uri`, `filename`, `s3_bucket`+`s3_key` and `local_code_dir`. These types are mutually exclusive - you must give exactly one type.

`runtime` and `handler` are required for all types except `image_uri`.

The `s3_key` is the file name of the deployment zip in `s3_bucket`. If it is using a prefix skip the leading slash e.g. `"folder/file.zip"`.

## `image_uri` - container image (ECR)

Fetch the function code from a container image in ECR.

## `filename`+`source_code_hash` - deployment package upload from local file

The code bundle is in a zip file at the given local path.

The file [may not exceed 50MB](https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html#function-configuration-deployment-and-execution). If you need a larger package, you must use one of the other types.

`source_code_hash` is the base64-encoded SHA256 hash of the zip file (if you're using an `archive_file` to generate the file, this is the [`output_base64sha256` attribute](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/resources/file#output_base64sha256-1); otherwise you probably want [`filebase64sha256()`](https://developer.hashicorp.com/terraform/language/functions/filebase64sha256)). This is optional but strongly encouraged, to make sure the lambda is updated when the zip changes, and to prevent cases where targeted or double applies are needed.

## `s3_bucket`+`s3_key` - deployment package upload from S3

The code bundle is in a zip file in the given S3 bucket and key. The executing role needs read access to the bucket.

Despite the input name `image_update_on_push` including the word "image", this option does now additionally handle lambda updates when the original zip in `s3_bucket` is copied over by a new upload. A backup of the previous lambda will be made by the lambda_image_updater to the same bucket at: s3-bucket/s3_path/short_func_name/%Y-%m-%d-%H-%M-%S.zip e.g.

* function-name = "myapp_ping-fun-dev-ew2-mainaccount"
* s3-bucket = "lambda-upload-s3-dev-ew2-mainaccount"
* s3-key = "myapp/ping.zip"

is backed up to:

* lambda-upload-s3-dev-ew2-mainaccount/myapp/ping/2025-03-31-22-36-06.zip


NB This deployment zip should not be created with terraform's aws_s3_object because terraform will constantly try to put the original zip back on each apply.

## `local_code_dir` - build and upload a deployment package from local source

The source code can be found at the given local directory. This is packaged and uploaded for you - via S3 if `s3_bucket` is specified, otherwise directly uploaded (see aforementioned [50MB limit](https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html#function-configuration-deployment-and-execution)).

The local zip files are placed in a directory named `.lambda_build_cache` in the root of the stack; these are ephemeral and should not be checked in to source control (include the directory in your .gitignore).
It is expected that the first execution of clean_old_builds will not work until this directory exists. Re-apply if you get `./.lambda_build_cache: No such file or
│ directory`.

If you are calling this module from within another module (the usual situation), rather than a stack, prefix this with `${path.module}/`.

### Notes on using external libraries

The module understands Python's `requirements.txt` and will install the dependencies listed therein if not already present. You will need `pip` installed for this. It could easily be extended to do similar for node.js packages, etc. You don't need to install anything that's [natively included in the runtime](https://www.feitsui.com/en/article/2). The error "Provider produced inconsistent final plan" can happen if you have updated requirements.txt; re-run the `terraform apply` again and it will run cleanly.

As the package is built locally, any libraries will be downloaded for your local machine OS and CPU architecture, which may not match the Lambda environment. You must therefore **only use libraries containing native Python code**, which do not need any OS-specific binary components. Additionally, the build does not make any provision for any automated testing of the code before deployment, so it is really only suited to simple and lightweight functions. If this does not meed your requirements, you will need to use one of the other package types, and a suitable external pipeline to build, test and deliver it.

You can add new dependencies and they will automatically be picked up, but you will need to manually clean up anything you remove. It is good practice to update libraries periodically, to pick up bug and security fixes - just run `pip install -r requirements.txt -t . --upgrade` in the directory. You will obviously need to test after this.

All the library files need to be checked into git.
