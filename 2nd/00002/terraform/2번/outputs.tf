###############################################################################
# outputs.tf
###############################################################################

output "alb_dns" {
  description = "채점 2-3-B / 2-5 에서 사용하는 ALB DNS"
  value       = aws_lb.alb.dns_name
}

output "ec2_instance_id" {
  value = aws_instance.app.id
}

output "kinesis_stream_name" {
  value = aws_kinesis_stream.orders.name
}

output "flink_application_name" {
  description = "CloudFormation 스택으로 생성되는 Studio Notebook"
  value       = var.flink_app_name
}

output "flink_stack_name" {
  value = aws_cloudformation_stack.flink_studio.name
}

output "test_commands" {
  description = "배포 후 확인 명령"
  value = <<-EOT
    export ALB_DNS=${aws_lb.alb.dns_name}
    curl -s http://$ALB_DNS/health
    curl -s -X POST http://$ALB_DNS/order | jq .
    curl -s -X POST http://$ALB_DNS/orders/generate | jq '.generated'
  EOT
}
