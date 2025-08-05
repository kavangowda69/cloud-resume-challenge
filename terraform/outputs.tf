output "website_url" {
  description = "Public URL of the S3 static website"
  value       = aws_s3_bucket.resume_bucket.website_endpoint
}
output "api_url" {
  description = "Invoke URL for the API Gateway"
  value       = aws_apigatewayv2_api.api.api_endpoint
}
