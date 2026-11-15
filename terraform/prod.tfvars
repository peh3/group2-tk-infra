environment           = "prod"
project_name          = "group2-tk-prod"
vpc_cidr              = "10.1.0.0/16" # Different CIDR to avoid IP overlap
aws_region            = "ap-southeast-1"
# ==========================================================
aurora_instance_count = 2             # High Availability (1 Writer, 1 Reader)
aurora_max_capacity   = 4             # More compute for production