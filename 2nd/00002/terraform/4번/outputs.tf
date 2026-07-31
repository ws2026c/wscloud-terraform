###############################################################################
# outputs.tf
###############################################################################

output "msk_cluster_arn" {
  value = aws_msk_cluster.main.arn
}

output "msk_bootstrap_brokers_sasl_iam" {
  value = aws_msk_cluster.main.bootstrap_brokers_sasl_iam
}

output "producer_instance_id" {
  value = aws_instance.producer.id
}

output "dynamodb_table" {
  value = aws_dynamodb_table.sensor.name
}

output "alert_bucket" {
  value = aws_s3_bucket.alert.id
}

output "check_commands" {
  value = <<-EOT
    export AWS_DEFAULT_REGION=${var.region}
    CLUSTER_ARN=${aws_msk_cluster.main.arn}
    BUCKET_NAME=${aws_s3_bucket.alert.id}

    aws kafka describe-cluster --cluster-arn $CLUSTER_ARN \
      --query "ClusterInfo.[ClusterName,State,CurrentBrokerSoftwareInfo.KafkaVersion,BrokerNodeGroupInfo.InstanceType,ClientAuthentication.Sasl.Iam.Enabled]" --output text

    aws dynamodb scan --table-name ${aws_dynamodb_table.sensor.name} --max-items 1 \
      --query "Items[0].{sensorId:sensorId.S,temperature:temperature.S,status:status.S}" --output json
  EOT
}
