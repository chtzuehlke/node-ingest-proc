provider "aws" {
  region = "eu-west-2"
}

####

resource "aws_sqs_queue" "apiGatewayEvents" {
  name = "cht-test-ingest-lambda"
}

resource "aws_sqs_queue" "apiGatewayResponses" {
  name = "cht-test-ingest-lambda2"
}

####

resource "aws_iam_role" "ingest" {
  name = "cht-test-ingest-lambda"

  assume_role_policy = <<-EOT
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                    "Service": "lambda.amazonaws.com"
                },
                "Effect": "Allow",
                "Sid": ""
            }
        ]
    }
  EOT

  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]

  inline_policy {
    name = "sqs"

    policy = <<-EOT
        {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Action": "sqs:SendMessage",
                    "Effect": "Allow",
                    "Resource": "${aws_sqs_queue.apiGatewayEvents.arn}",
                    "Sid": ""
                }
            ]
        }
    EOT
  }
}

data "archive_file" "ingest" {
  type        = "zip"
  output_path = "${path.module}/lambda_function_payload.zip"
  source {
    content  = <<-EOT
        'use strict';
        const AWS = require('aws-sdk');
        const sqs = new AWS.SQS({ apiVersion: '2012-11-05' });
        exports.ingest = async event => {
            console.log(event);
            const result = await sqs.sendMessage({
                MessageBody: JSON.stringify(event),
                QueueUrl: process.env.TARGET_QUEUE,
            }).promise();
            return {
                statusCode: 200,
                body: JSON.stringify(result)
            };
        };
      EOT
    filename = "handler.js"
  }
}

resource "aws_lambda_function" "ingest" {
  filename         = data.archive_file.ingest.output_path
  function_name    = "cht-test-ingest-lambda"
  role             = aws_iam_role.ingest.arn
  handler          = "handler.ingest"
  source_code_hash = data.archive_file.ingest.output_sha
  runtime          = "nodejs12.x"
  environment {
    variables = {
      TARGET_QUEUE = aws_sqs_queue.apiGatewayEvents.id
    }
  }
}

####

resource "aws_iam_role" "process" {
  name = "cht-test-ingest-lambda2"

  assume_role_policy = <<-EOT
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                    "Service": "lambda.amazonaws.com"
                },
                "Effect": "Allow",
                "Sid": ""
            }
        ]
    }
  EOT

  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]

  inline_policy {
    name = "sqs"

    policy = <<-EOT
        {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Action": "lambda:InvokeFunction",
                    "Effect": "Allow",
                    "Resource": "${aws_lambda_function.direct.arn}",
                    "Sid": ""
                },
                {
                    "Action": [
                        "sqs:ReceiveMessage",
                        "sqs:DeleteMessage",
                        "sqs:GetQueueAttributes"
                    ],
                    "Effect": "Allow",
                    "Resource": "${aws_sqs_queue.apiGatewayEvents.arn}",
                    "Sid": ""
                }
            ]
        }
    EOT
  }
}

data "archive_file" "process" {
  type        = "zip"
  output_path = "${path.module}/lambda_function_payload2.zip"
  source {
    content  = <<-EOT
        'use strict';
        const AWS = require('aws-sdk');
        const lambda = new AWS.Lambda();
        exports.process = async event => {
            console.log(event);
            const record = event["Records"][0];
            const result = await lambda.invoke({
                FunctionName: process.env.TARGET_LAMBDA,
                Payload: record["body"]
            }).promise();
            return "ok";
        };
      EOT
    filename = "handler.js"
  }
}

resource "aws_lambda_function" "process" {
  filename                       = data.archive_file.process.output_path
  function_name                  = "cht-test-ingest-lambda2"
  role                           = aws_iam_role.process.arn
  handler                        = "handler.process"
  source_code_hash               = data.archive_file.process.output_sha
  runtime                        = "nodejs12.x"
  reserved_concurrent_executions = 1
  environment {
    variables = {
      TARGET_LAMBDA = aws_lambda_function.direct.arn
    }
  }
}

resource "aws_lambda_event_source_mapping" "event_source_mapping" {
  batch_size       = 1
  event_source_arn = aws_sqs_queue.apiGatewayEvents.arn
  enabled          = true
  function_name    = aws_lambda_function.process.arn
}

####

resource "aws_iam_role" "direct" {
  name = "cht-test-ingest-lambda3"

  assume_role_policy = <<-EOT
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                    "Service": "lambda.amazonaws.com"
                },
                "Effect": "Allow",
                "Sid": ""
            }
        ]
    }
  EOT

  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]

  inline_policy {
    name = "sqs"

    policy = <<-EOT
        {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Action": "sqs:SendMessage",
                    "Effect": "Allow",
                    "Resource": "${aws_sqs_queue.apiGatewayResponses.arn}",
                    "Sid": ""
                }
            ]
        }
    EOT
  }
}

data "archive_file" "direct" {
  type        = "zip"
  output_path = "${path.module}/lambda_function_payload3.zip"
  source {
    content  = <<-EOT
        'use strict';
        const AWS = require('aws-sdk');
        const sqs = new AWS.SQS({ apiVersion: '2012-11-05' });
        exports.direct = async event => {
            console.log(event);
            const result = await sqs.sendMessage({
                MessageBody: event["body"],
                QueueUrl: process.env.TARGET_QUEUE
            }).promise();
            return {
                statusCode: 200,
                body: event["body"]
            };
        };
      EOT
    filename = "handler.js"
  }
}

resource "aws_lambda_function" "direct" {
  filename         = data.archive_file.direct.output_path
  function_name    = "cht-test-ingest-lambda3"
  role             = aws_iam_role.direct.arn
  handler          = "handler.direct"
  source_code_hash = data.archive_file.direct.output_sha
  runtime          = "nodejs12.x"
  environment {
    variables = {
      TARGET_QUEUE = aws_sqs_queue.apiGatewayResponses.id
    }
  }
}

####

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_apigatewayv2_api" "this" {
  name          = "cht-test-ingest-lambda"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "this" {
  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
  integration_uri    = aws_lambda_function.ingest.arn
}

resource "aws_lambda_permission" "this" {
  statement_id  = "AllowAPIGatewayInvoke"
  function_name = aws_lambda_function.ingest.function_name
  action        = "lambda:InvokeFunction"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.this.id}/*/*/{proxy+}"
}

resource "aws_apigatewayv2_route" "this" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "POST /a/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.this.id}"
}

resource "aws_apigatewayv2_stage" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true
  default_route_settings {
    detailed_metrics_enabled = false
    logging_level            = "OFF"
    throttling_burst_limit   = 10
    throttling_rate_limit    = 10
  }
}

#

resource "aws_apigatewayv2_integration" "this2" {
  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
  integration_uri    = aws_lambda_function.direct.arn
}

resource "aws_lambda_permission" "this2" {
  statement_id  = "AllowAPIGatewayInvoke"
  function_name = aws_lambda_function.direct.function_name
  action        = "lambda:InvokeFunction"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.this.id}/*/*/{proxy+}"
}

resource "aws_apigatewayv2_route" "this2" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "POST /b/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.this2.id}"
}

#

output "url" {
  value = aws_apigatewayv2_api.this.api_endpoint
}

output "result_queue" {
  value = aws_sqs_queue.apiGatewayResponses.id
}
