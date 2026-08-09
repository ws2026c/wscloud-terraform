variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

variable "user_number" {
  description = "Candidate Number (e.g., 101)"
  type        = string
  default     = "125"
}

variable "random_suffix" {
  description = "Random 4-letter English characters"
  type        = string
  default     = "abcd"
}

variable "admin_iam_arn" {
  description = "IAM User or Role ARN for KMS Key Administrator (Must not be root)"
  type        = string
  default     = "arn:aws:iam::602620439352:user/On-Demend"
}