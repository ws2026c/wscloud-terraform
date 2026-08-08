resource "aws_security_group" "alb_sg" {
  name        = "wskorea26-book-alb-sg"
  description = "Security group for wskorea26-book-alb"
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
    Name = "wskorea26-book-alb-sg"
  }
}

resource "aws_lb" "book_alb" {
  name               = "wskorea26-book-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.pub_c.id, aws_subnet.pub_d.id]

  tags = {
    Name = "wskorea26-book-alb"
  }
}

resource "aws_lb_target_group" "ip_tg" {
  name        = "wskorea26-ip-tg"
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
  }

  tags = {
    Name = "wskorea26-ip-tg"
  }
}

resource "aws_lb_target_group" "lambda_tg" {
  name        = "wskorea26-lambda-tg"
  target_type = "lambda"

  tags = {
    Name = "wskorea26-lambda-tg"
  }
}


resource "aws_lambda_permission" "alb_lambda_permission" {
  statement_id  = "AllowExecutionFromALB"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.book_lambda.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda_tg.arn
}

resource "aws_lb_listener" "http_80" {
  load_balancer_arn = aws_lb.book_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "403 Forbidden"
      status_code  = "403"
    }
  }
}

resource "aws_lb_listener_rule" "rule_post_app" {
  listener_arn = aws_lb_listener.http_80.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ip_tg.arn
  }

  condition {
    http_request_method {
      values = ["POST"]
    }
  }

  condition {
    path_pattern {
      values = ["/book", "/v1/book"]
    }
  }

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = ["wskorea26-cf"]
    }
  }
}

resource "aws_lb_listener_rule" "rule_get_lambda" {
  listener_arn = aws_lb_listener.http_80.arn
  priority     = 20

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
      values = ["/book*", "/reserv_query*"]
    }
  }

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = ["wskorea26-cf"]
    }
  }
}