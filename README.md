# Overview
This repo provides a sample Terraform config for Databricks Auto Loader resources.

# Motivation
Many data/cloud teams prefer to define all of their cloud infrastructure using Terraform or other IaC tools, such as CloudFormation. Databricks' documentation does not include examples of how to do this. 

# Background
Databricks [Auto Loader](https://docs.databricks.com/spark/latest/structured-streaming/auto-loader.html) includes a "file notifications" mode for efficiently ingesting new files from cloud storage (S3, ADLS, GCS).

Under the hood, Databricks is just [creating new cloud resources](https://docs.databricks.com/spark/latest/structured-streaming/auto-loader.html#file-notification) for your provider of choice. On AWS, this consists of:

- An S3 bucket notification
- An SNS topic to receive the notifications
- An SQS queue to receive messages from the SNS topic
- Appropriate IAM policies to enable inter-service communication

Databricks can then consume messages from the SQS queue in microbatches.

Some teams will prefer to define these resources themselves in order to keep as much of their cloud infrastructure managed as IaC as possible. In addition, some teams will not have granted the Databricks IAM role sufficient permissions to generate these resources.
