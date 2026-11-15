
output "infra_deployer_role_arns" {
  description = "The ARNs of the generated infrastructure deployment roles"
  # This loops through all generated roles and creates a map of their ARNs
  value       = { for k, v in aws_iam_role.infra_deployer_role : k => v.arn }
}