resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "wskorea26-s3-oac"
  description                       = "OAC for S3 concert bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
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
