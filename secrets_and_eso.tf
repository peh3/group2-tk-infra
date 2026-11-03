locals {
  cluster_name = "group2-tk-cluster"
}

resource "aws_secretsmanager_secret" "github_pat" {
  name                    = "group2-tk/argocd/github-pat"
  description             = "GitHub PAT for Argo CD repository access"
  recovery_window_in_days = 0 # Immediate deletion upon terraform destroy

  tags = {
    Environment = "sandbox"
    ManagedBy   = "terraform"
  }
}

resource "aws_eks_addon" "pod_identity" {
  cluster_name = local.cluster_name
  addon_name   = "eks-pod-identity-agent"
}

# Trust policy for EKS Pod Identity
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

# Least-privilege policy allowing read access ONLY to the github-pat secret
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

resource "aws_eks_pod_identity_association" "eso_association" {
  cluster_name    = local.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.eso_role.arn

  depends_on = [aws_eks_addon.pod_identity]
}