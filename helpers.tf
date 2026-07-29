module "helpers" {
  source = "git::https://github.com/MartinSG98/tf-module-helpers.git?ref=1.0.0"

  environment       = var.environment
  account_shortname = var.account_shortname
  region            = var.region
}
