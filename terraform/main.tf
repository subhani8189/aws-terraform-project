provider "aws" {
  region = var.aws_region
}


# --- VARIABLES ---
variable "project_prefix" {
  default = "s3_subbu_818980" 
}

# --- S3 BUCKETS ---
resource "aws_s3_bucket" "raw_bucket" {
  bucket = "${var.project_prefix}-raw"
  force_destroy = true
}

resource "aws_s3_bucket" "processed_bucket" {
  bucket = "${var.project_prefix}-processed"
  force_destroy = true
}

# --- IAM ROLE FOR LAMBDA ---
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_prefix}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_admin" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess" # Using Admin for simplicity in learning
}

# --- LAMBDA FUNCTION ---
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "../lambda/processor.py"
  output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "processor" {
  filename         = "lambda_function.zip"
  function_name    = "${var.project_prefix}-processor"
  role             = aws_iam_role.lambda_role.arn
  handler          = "processor.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  environment {
    variables = { DEST_BUCKET = aws_s3_bucket.processed_bucket.bucket }
  }
}

# --- S3 TRIGGER ---
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.raw_bucket.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.raw_bucket.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.processor.arn
    events              = ["s3:ObjectCreated:*"]
  }
  depends_on = [aws_lambda_permission.allow_s3]
}

# --- GLUE & ATHENA (DATA ANALYTICS) ---
resource "aws_glue_catalog_database" "analytics_db" {
  name = "${var.project_prefix}_db"
}

resource "aws_iam_role" "glue_role" {
  name = "${var.project_prefix}-glue-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "glue.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "glue_s3" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_glue_crawler" "crawler" {
  database_name = aws_glue_catalog_database.analytics_db.name
  name          = "${var.project_prefix}-crawler"
  role          = aws_iam_role.glue_role.arn
  s3_target {
    path = "s3://${aws_s3_bucket.processed_bucket.bucket}"
  }
}
