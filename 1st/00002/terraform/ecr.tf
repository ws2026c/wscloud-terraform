resource "aws_ecr_repository" "book_repo" {
  name                 = "wskorea26-book-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }

  tags = {
    Name = "wskorea26-book-repo"
  }
}