output "job_queue" {
  value = aws_batch_job_queue.main.name
}

output "job_definition" {
  value = aws_batch_job_definition.run.name
}

output "results_bucket" {
  value = aws_s3_bucket.results.id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.runner.repository_url
}

output "capacity_type" {
  value = var.use_spot ? "FARGATE_SPOT" : "FARGATE"
}
