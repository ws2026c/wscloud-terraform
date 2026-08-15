output "lattice_service_domain" {
  value = aws_vpclattice_service.order_service.dns_entry[0].domain_name
}

output "client_ec2_public_ip" {
  value = aws_instance.client_ec2.public_ip
}

output "service_ec2_id" {
  value = aws_instance.service_ec2.id
}
