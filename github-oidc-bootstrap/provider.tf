terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

}

# The default_tags block must go inside the provider definition
provider "aws" {
  region = "ap-southeast-1" # Add your region here

  default_tags {
    tags = {
      Project = "capstone-project-group-02"
    }
  }
}