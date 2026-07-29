resource "terraform_data" "install_python_dependencies" {
  provisioner "local-exec" {
    command = "pip install -r ${var.local_code_dir}/requirements.txt -t ${var.local_code_dir}/"
  }

  triggers_replace = {
    # Re-run if the file changes
    requirements = filesha256("${var.local_code_dir}/requirements.txt")
  }

  count = var.local_code_dir != null ? (fileexists("${var.local_code_dir}/requirements.txt") ? 1 : 0) : 0
}

# Generates a new UUID each time the code changes, which we use to force a rebuild/redeploy of the package
resource "random_uuid" "lambda_code_hash" {
  keepers = {
    # Generates a map of filenames and their content hashes - if any change, this resource generates a new random UUID
    for filename in fileset(var.local_code_dir, "**") : filename => filesha256("${var.local_code_dir}/${filename}")
  }

  # Make sure we run after any libraries have downloaded, as this adds more files
  # TODO: despite this we get "Provider produced inconsistent final plan" when requirements.txt changes; re-trying will succeed
  depends_on = [terraform_data.install_python_dependencies]

  count = var.local_code_dir != null ? 1 : 0
}

# Create the zip file
data "archive_file" "local_package" {
  type       = "zip"
  source_dir = "${var.local_code_dir}/"
  # We drop packages in a dir in the stack root. This should be in the .gitignore; these packages are transient and ephemeral
  output_path = "${path.root}/.lambda_build_cache/${var.name_prefix}-fun-${module.helpers.name_suffix}.${random_uuid.lambda_code_hash[0].id}.zip"

  count = var.local_code_dir != null ? 1 : 0
}

# Work around an issue where the same local code, built on different engineers' machines, produces a different output_base64sha256
# This causes an unnecessary change of the lambda and all dependent resources
# Replacement (picking up the new hash) will be triggered if the source code *actually* changes
resource "terraform_data" "source_code_hash" {
  input = data.archive_file.local_package[0].output_base64sha256
  lifecycle {
    ignore_changes = [input]
  }
  triggers_replace = random_uuid.lambda_code_hash[0].id
  count            = var.local_code_dir != null ? 1 : 0
}


# Clean old zip versions from the cache (the above data source just builds new ones)
resource "terraform_data" "clean_old_builds" {
  provisioner "local-exec" {
    # Note: this may not work on Windows
    command = "[ -d '${path.root}/.lambda_build_cache' ] && find '${path.root}/.lambda_build_cache' -name '${var.name_prefix}-fun-${module.helpers.name_suffix}.*.zip' -not -name '${var.name_prefix}-fun-${module.helpers.name_suffix}.${random_uuid.lambda_code_hash[0].id}.zip' -delete"
  }

  triggers_replace = {
    # Re-run if we've repackaged
    code_hash = random_uuid.lambda_code_hash[0].id
  }

  count = var.local_code_dir != null ? 1 : 0
}

# Upload the zip to S3, if we are given a bucket
resource "aws_s3_object" "package_upload" {
  bucket = var.s3_bucket
  key    = replace(data.archive_file.local_package[0].output_path, "/^.*\\//", "") # Just the filename part
  source = data.archive_file.local_package[0].output_path
  region = var.region

  tags = local.tags

  count = var.local_code_dir != null && var.s3_bucket != null ? 1 : 0
}
