#!/bin/bash

terraform apply --auto-approve

sleep 1

curl -s -H "Content-Type: application/json" -d '{"source":"indirect2"}' $(terraform output url | jq -r ".")/a/ | jq
curl -s -H "Content-Type: application/json" -d '{"source":"direct2"}' $(terraform output url | jq -r ".")/b/ | jq

sleep 2

aws sqs receive-message --queue-url $(terraform output result_queue | jq -r ".") | jq -r ".Messages[0].Body"
aws sqs receive-message --queue-url $(terraform output result_queue | jq -r ".") | jq -r ".Messages[0].Body"
aws sqs purge-queue --queue-url $(terraform output result_queue | jq -r ".")
