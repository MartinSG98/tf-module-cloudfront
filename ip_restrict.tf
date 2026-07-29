module "ip_restrict" {
  source = "git::https://github.com/MartinSG98/tf-module-lambda.git?ref=1.0.0"

  count = length(var.allowed_cidrs) > 0 ? 1 : 0

  name_prefix      = "ip_restrict_${var.name_prefix}"
  filename         = archive_file.ip_restrict_code[0].output_path
  source_code_hash = archive_file.ip_restrict_code[0].output_base64sha256
  timeout          = 1

  runtime           = "python3.13"
  handler           = "main.lambda_handler"
  environment       = var.environment
  is_lambda_at_edge = true
  region            = "us-east-1"
  tags              = var.tags
}

resource "archive_file" "ip_restrict_code" {
  count       = length(var.allowed_cidrs) > 0 ? 1 : 0
  type        = "zip"
  output_path = "${path.root}/.lambda_build_cache/ip_restrict.zip"

  source {
    content  = templatefile("${path.module}/functions/ip_restrict/main.py.tftpl", { allowed_cidrs = var.allowed_cidrs })
    filename = "main.py"
  }
}
