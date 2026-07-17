# ── S3 State Bucket ─────────────────────────────────────────────────────────
# prevent_destroy 防止 terraform destroy 意外刪除 state bucket，
# 即使有 state 中的所有資源被刪除，bucket 本身也不會被刪除。
resource "aws_s3_bucket" "tf_state" {
  bucket = var.tf_state_bucket

  lifecycle {
    prevent_destroy = true
  }
}

# ── 版本控制（可還原被覆寫的 state 檔案）────────────────────────────────────
resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ── 伺服器端加密（AES256）────────────────────────────────────────────────────
resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ── 封鎖所有公開存取 ──────────────────────────────────────────────────────────
resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}
