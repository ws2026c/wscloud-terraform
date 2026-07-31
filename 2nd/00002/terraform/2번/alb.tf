###############################################################################
# alb.tf - EC2 외부 트래픽 처리용 Application Load Balancer
#   채점 2-2 : Listener 80 HTTP / TargetGroup wsc2026-analytics-tg Port 5000
#   채점 2-5 : curl http://$ALB_DNS/health -> {"status":"healthy"}
###############################################################################

resource "aws_lb" "alb" {
  name               = var.alb_name
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for n in local.public_subnet_names : aws_subnet.this[n].id]

  idle_timeout = 60

  tags = { Name = var.alb_name }
}

resource "aws_lb_target_group" "tg" {
  name        = var.tg_name
  port        = var.app_port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 30

  tags = { Name = var.tg_name }
}

resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.app.id
  port             = var.app_port
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}
