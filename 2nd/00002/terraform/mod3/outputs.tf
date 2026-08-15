###############################################################################
# outputs.tf
###############################################################################

output "instance_id" {
  value = aws_instance.monitored.id
}

output "security_group_id" {
  value = aws_security_group.ec2.id
}

output "sns_topic_arn" {
  value = aws_sns_topic.alert.arn
}

output "lambda_functions" {
  value = sort(keys(local.lambda_functions))
}

output "event_rules" {
  value = sort(keys(local.event_rules))
}

output "config_rules" {
  value = [aws_config_config_rule.sg_ssh.name, aws_config_config_rule.required_tags.name]
}

output "remediation_test_commands" {
  description = "채점 3-0 이 수행하는 위반 유발 명령"
  value       = <<-EOT
    export AWS_DEFAULT_REGION=${var.region}
    INSTANCE_ID=${aws_instance.monitored.id}
    SG_ID=${aws_security_group.ec2.id}

    aws ec2 stop-instances --instance-ids $INSTANCE_ID
    aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0

    # 2~3분 후
    aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].State.Name" --output text
    aws ec2 describe-security-groups --group-ids $SG_ID --query "SecurityGroups[0].IpPermissions | length(@)" --output text
  EOT
}
