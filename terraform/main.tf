terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# === S3 WEBSITE ===
resource "aws_s3_bucket" "resume_bucket" {
  bucket        = "kavan-cloud-resume-bucket-fixed-1234"
  force_destroy = true
}

resource "aws_s3_bucket_website_configuration" "website_config" {
  bucket = aws_s3_bucket.resume_bucket.id

  index_document { suffix = "index.html" }
  error_document { key    = "error.html" }
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket                  = aws_s3_bucket.resume_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "allow_public_access" {
  bucket = aws_s3_bucket.resume_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement: [{
      Sid: "PublicReadGetObject",
      Effect: "Allow",
      Principal: "*",
      Action: ["s3:GetObject"],
      Resource: "${aws_s3_bucket.resume_bucket.arn}/*"
    }]
  })
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.resume_bucket.id
  key          = "index.html"
  source       = "../index.html"
  content_type = "text/html"
}

# === DYNAMODB ===
resource "aws_dynamodb_table" "visitor_table" {
  name         = "visitor-count"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# === IAM ROLE + POLICIES FOR LAMBDA ===
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

# Basic execution policy
resource "aws_iam_policy_attachment" "lambda_basic_execution" {
  name       = "lambda-basic-execution"
  roles      = [aws_iam_role.lambda_exec_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# S3 Read access
resource "aws_iam_policy_attachment" "lambda_s3_read" {
  name       = "lambda-s3-read-access"
  roles      = [aws_iam_role.lambda_exec_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# DynamoDB access
resource "aws_iam_policy" "dynamodb_access" {
  name        = "lambda-dynamodb-policy"
  description = "Allow Lambda to access DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement: [{
      Effect = "Allow",
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem"
      ],
      Resource = aws_dynamodb_table.visitor_table.arn
    }]
  })
}

resource "aws_iam_policy_attachment" "attach_dynamodb_access" {
  name       = "attach-dynamodb-access"
  roles      = [aws_iam_role.lambda_exec_role.name]
  policy_arn = aws_iam_policy.dynamodb_access.arn
}

# === LAMBDA FUNCTION ===
resource "aws_lambda_function" "visitor_counter" {
  function_name = "visitorCounterFunction"
  handler       = "visitor_counter.lambda_handler"
  runtime       = "python3.12"
  role          = aws_iam_role.lambda_exec_role.arn
  s3_bucket     = "kavan-lambda-code-us-east-1"
  s3_key        = "visitor-function.zip"
  timeout       = 3

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.visitor_table.name
    }
  }
}

# === API GATEWAY ===
resource "aws_apigatewayv2_api" "api" {
  name          = "visitor-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.visitor_counter.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "lambda_route" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /visitor"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_counter.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

# === OUTPUT ===
output "website_url" {
  value = aws_s3_bucket_website_configuration.website_config.website_endpoint
}

output "api_url" {
  value = aws_apigatewayv2_api.api.api_endpoint
}
