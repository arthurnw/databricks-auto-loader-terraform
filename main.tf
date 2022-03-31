terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  profile = "work-personal-admin" # SPECIFY AWS PROFILE
  region  = "us-east-1"           # SPECIFY AWS REGION
}

# S3 bucket source
resource "aws_s3_bucket" "source_s3_bucket" {
  bucket = "anw_source_s3_bucket" # SPECIFY BUCKET NAME
}

# SNS + policy
resource "aws_sns_topic" "databricks_auto_ingest_source_s3_bucket" {
  name            = "databricks-auto-ingest-source-s3-bucket"
  delivery_policy = <<-EOF
{
    "http": {
        "defaultHealthyRetryPolicy": {
            "numRetries": 3,
            "numNoDelayRetries": 0,
            "minDelayTarget": 20,
            "maxDelayTarget": 20,
            "numMinDelayRetries": 0,
            "numMaxDelayRetries": 0,
            "backoffFunction": "linear"
        },
        "disableSubscriptionOverrides": false
    }
}
EOF
}

resource "aws_sns_topic_policy" "databricks_auto_ingest_source_s3_bucket" {
  arn    = aws_sns_topic.databricks_auto_ingest_source_s3_bucket.arn
  policy = data.aws_iam_policy_document.databricks_auto_ingest_source_s3_bucket_topic_policy.json
}

data "aws_iam_policy_document" "databricks_auto_ingest_source_s3_bucket_topic_policy" {
  statement {
    sid    = "allow-s3-notification-databricks-auto-ingest-source-s3-bucket-topic"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.databricks_auto_ingest_source_s3_bucket.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.source_s3_bucket.arn]
    }
  }
}

# SQS + policy
resource "aws_sqs_queue" "databricks_auto_ingest_source_s3_bucket" {
  name = "databricks-auto-ingest-source-s3-bucket-queue"
}

resource "aws_sqs_queue_policy" "databricks_auto_ingest_source_s3_bucket" {
  queue_url = aws_sqs_queue.databricks_auto_ingest_source_s3_bucket.id
  policy    = data.aws_iam_policy_document.databricks_auto_ingest_source_s3_bucket_queue_policy.json
}

data "aws_iam_policy_document" "databricks_auto_ingest_source_s3_bucket_queue_policy" {
  statement {
    sid    = "allow-s3-notification-databricks-auto-ingest-source-s3-bucket-queue"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.databricks_auto_ingest_source_s3_bucket.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.databricks_auto_ingest_source_s3_bucket.arn]
    }
  }
}

# See Terraform docs about cross-account subscriptions: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription
resource "aws_sns_topic_subscription" "databricks_auto_ingest_source_s3_bucket_sns_sqs_target" {
  topic_arn = aws_sns_topic.databricks_auto_ingest_source_s3_bucket.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.databricks_auto_ingest_source_s3_bucket.arn
}

# Bucket notification on source-s3-bucket with SNS topic as destination
resource "aws_s3_bucket_notification" "databricks_auto_ingest_source_s3_bucket_notification" {
  bucket = aws_s3_bucket.source_s3_bucket
  topic {
    topic_arn = aws_sns_topic.databricks_auto_ingest_source_s3_bucket.arn
    events = [
      "s3:ObjectCreated:*",
      "s3:ObjectRemoved:*"
    ]
  }
}

# Auto Loader role, policy, attachment
resource "aws_iam_role" "databricks_shared_ec2_role" {
  name               = "DatabricksSharedEC2Role"
  assume_role_policy = <<-EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Action": "sts:AssumeRole",
        "Principal": {
            "Service": "ec2.amazonaws.com"
        },
    "Effect": "Allow",
    "Sid": ""
    }]
}
EOF
}

resource "aws_iam_instance_profile" "databricks_shared_instance_profile" {
  name = "shared-instance-profile"
  role = aws_iam_role.databricks_shared_ec2_role.name
}

# Policy to allow Databricks EC2s to consume resources for Auto Loader
resource "aws_iam_policy" "databricks_auto_ingest_source_s3_bucket_ec2_policy" {
  name        = "databricks-auto-ingest-source-s3-bucket-ec2-policy"
  description = "Policy to allow consumption of Databricks Auto Loader resources"
  policy      = data.aws_iam_policy_document.databricks_auto_ingest_source_s3_bucket_ec2_policy.json
}

data "aws_iam_policy_document" "databricks_auto_ingest_source_s3_bucket_ec2_policy" {
  statement {
    sid    = "DatabricksAutoLoaderUse"
    effect = "Allow"
    actions = [
      "s3:GetBucketNotification",
      "sns:ListSubscriptionsByTopic",
      "sns:GetTopicAttributes",
      "sns:TagResource",
      "sns:Publish",
      "sqs:DeleteMessage",
      "sqs:ReceiveMessage",
      "sqs:SendMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
      "sqs:TagQueue",
      "sqs:ChangeMessageVisibility"
    ]
    resources = [
      aws_sqs_queue.databricks_auto_ingest_source_s3_bucket.arn,
      aws_sns_topic.databricks_auto_ingest_source_s3_bucket.arn,
      aws_s3_bucket.source_s3_bucket.arn
    ]
  }
}

resource "aws_iam_role_policy_attachment" "test-attach" {
  role       = aws_iam_role.databricks_shared_ec2_role.name
  policy_arn = aws_iam_policy.databricks_auto_ingest_source_s3_bucket_ec2_policy.arn
}