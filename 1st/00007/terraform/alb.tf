resource "aws_security_group" "alb_sg" {
  name        = "unicorn-alb-sg"
  description = "Security Group for Internal ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "unicorn-alb-sg"
  }
}

resource "aws_lb" "unicorn_alb" {
  name               = "unicorn-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.private[*].id

  tags = {
    Name = "unicorn-alb"
  }
}

resource "aws_lb_target_group" "app_tg" {
  name        = "unicorn-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "8080"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name = "unicorn-tg"
  }
}

resource "aws_lb_target_group" "lambda_tg" {
  name        = "unicorn-lambda-tg"
  target_type = "lambda"
}

resource "aws_lb_target_group_attachment" "lambda_attach" {
  target_group_arn = aws_lb_target_group.lambda_tg.arn
  target_id        = aws_lambda_function.get_booking.arn
  depends_on       = [aws_lambda_permission.alb_lambda_permission]
}

resource "aws_lambda_permission" "alb_lambda_permission" {
  statement_id  = "AllowExecutionFromALB"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_booking.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda_tg.arn
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.unicorn_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

resource "aws_lb_listener_rule" "get_booking_rule" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda_tg.arn
  }

  condition {
    http_request_method {
      values = ["GET"]
    }
  }

  condition {
    path_pattern {
      values = ["/v1/book"]
    }
  }
}
