# 1. Create the Staging Role in AWS
terraform init
terraform apply -var-file=staging.tfvars -auto-approve

# 2. Create the Prod Role in AWS
terraform init
terraform apply -var-file=prod.tfvars -auto-approve