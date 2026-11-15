# Force verification of the cluster in the current provider region
data "aws_eks_cluster" "cluster" {
  name       = "group2-tk-cluster"
  depends_on = [module.eks] # or [aws_eks_cluster.this]
}

# 1. AWS Secrets Manager Secret Container (Zero-leak pattern: value injected out-of-band)
resource "aws_secretsmanager_secret" "github_pat" {
  name                    = "group2-tk/argocd/github-pat"
  description             = "GitHub PAT for Argo CD repository access"
  recovery_window_in_days = 0 # Immediate deletion upon terraform destroy

  tags = {
    Environment = "sandbox"
    ManagedBy   = "terraform"
  }
}

# 2. EKS Pod Identity Agent Add-on
resource "aws_eks_addon" "pod_identity" {
  cluster_name = data.aws_eks_cluster.cluster.name
  addon_name   = "eks-pod-identity-agent"
}

# 3. IAM Role & Trust Policy for EKS Pod Identity
data "aws_iam_policy_document" "eso_pod_identity_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eso_role" {
  name               = "group2-tk-eso-role"
  assume_role_policy = data.aws_iam_policy_document.eso_pod_identity_trust.json
}

# 4. Scoped IAM Policy: strictly allows reading only the github-pat secret
resource "aws_iam_role_policy" "eso_secrets_policy" {
  name = "ReadArgoCDSecretsOnly"
  role = aws_iam_role.eso_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "${aws_secretsmanager_secret.github_pat.arn}*"
      }
    ]
  })
}

# 5. Pod Identity Association binding the IAM role to ESO's ServiceAccount
resource "aws_eks_pod_identity_association" "eso_association" {
  cluster_name    = data.aws_eks_cluster.cluster.name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.eso_role.arn

  depends_on = [
    aws_eks_addon.pod_identity,
    aws_iam_role_policy.eso_secrets_policy
  ]
}