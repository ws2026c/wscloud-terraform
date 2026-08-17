resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "wskorea26-s3-oac"
  description                       = "OAC for S3 concert bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_origin_request_policy" "alb_origin_request_policy" {
  name    = "wskorea26-alb-origin-request-policy"
  comment = "Policy to forward all query strings and headers to ALB"

  cookies_config {
    cookie_behavior = "all"
  }

  headers_config {
    header_behavior = "allViewer"
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}

resource "aws_cloudfront_distribution" "concert_cf" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "wskorea26-concert-cf"
  price_class         = "PriceClass_All"

  origin {
    domain_name              = aws_s3_bucket.concert_bucket.bucket_regional_domain_name
    origin_id                = "wskorea26-s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id
    origin_path              = "/web/main"

    custom_header {
      name  = "wskorea26-s3-access"
      value = "true"
    }
  }

  origin {
    domain_name = aws_lb.book_alb.dns_name
    origin_id   = "wskorea26-alb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-Origin-Verify"
      value = "wskorea26-cf"
    }
  }

  default_cache_behavior {
    target_origin_id       = "wskorea26-s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 31536000
  }

  ordered_cache_behavior {
    path_pattern             = "/book*"
    target_origin_id         = "wskorea26-alb-origin"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    origin_request_policy_id = aws_cloudfront_origin_request_policy.alb_origin_request_policy.id

    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "wskorea26-concert-cf"
  }
}

resource "aws_s3_bucket_policy" "s3_oac_policy" {
  bucket = aws_s3_bucket.concert_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.concert_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.concert_cf.arn
          }
        }
      }
    ]
  })
}