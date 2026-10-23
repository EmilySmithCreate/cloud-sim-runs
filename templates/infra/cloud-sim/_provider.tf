terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.72"
    }
  }

  # The state lives in the account it describes. The bucket, region and lock table carry the account id and the
  # stack's name, which are kept out of the files, so they are passed at init (sim_deploy.yml does this):
  #   terraform init -backend-config="bucket=<name>-tfstate-<account>" \
  #                  -backend-config="region=<region>" -backend-config="dynamodb_table=<name>-tf-locks"
  backend "s3" {
    key     = "cloud-sim/terraform.tfstate"
    encrypt = true
  }
}

provider "aws" {
  region = var.region

  # Refuse to touch any other account, whatever credentials happen to be loaded.
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Stack     = var.name
    }
  }
}

# The default VPC, on purpose. The jobs only need outbound access, to pull an image and write to S3, so they run in
# public subnets with a public IP. Private subnets would need a NAT gateway, about $32 a month, which is usually more
# than the compute.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}
