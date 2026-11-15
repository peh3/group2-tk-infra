# 1. Create the Staging Role in AWS
terraform init -backend-config=staging.s3.tfbackend
terraform apply -var-file=staging.tfvars -auto-approve

# 2. Create the Prod Role in AWS
terraform init -backend-config=prod.s3.tfbackend -reconfigure
terraform apply -var-file=prod.tfvars -auto-approve