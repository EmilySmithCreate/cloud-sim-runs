# Bucket names are global across all of AWS, so the account id makes this one unique.
resource "aws_s3_bucket" "results" {
  bucket        = "${var.name}-results-${var.aws_account_id}"
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "results" {
  bucket                  = aws_s3_bucket.results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioning, so that a finished result that is somehow overwritten can be recovered rather than argued about.
resource "aws_s3_bucket_versioning" "results" {
  bucket = aws_s3_bucket.results.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  # Scratch from runs that stopped early.
  rule {
    id     = "expire-partials"
    status = "Enabled"

    filter {
      prefix = "partial/"
    }

    expiration {
      days = 14
    }
  }

  # Finished results never expire; this only tidies the versions an overwrite leaves behind.
  rule {
    id     = "tidy-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_ecr_repository" "runner" {
  name                 = var.name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Keep the last ten images; only the newest is pulled.
resource "aws_ecr_lifecycle_policy" "runner" {
  repository = aws_ecr_repository.runner.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep the last ten images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
