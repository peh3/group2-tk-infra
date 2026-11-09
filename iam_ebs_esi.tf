# 1. Dedicated NEW IAM Role for EBS CSI Driver
# Trusts EKS Pod Identity (pods.eks.amazonaws.com)
resource "aws_iam_role" "ebs_csi" {
  name = "${var.project_name}-ebs-csi-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
}

# 2. Attach the AWS managed policy to the new role
resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# 3. Map the new Role directly to the Kubernetes ServiceAccount via Pod Identity
resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi.arn
}

resource "aws_iam_policy" "ebs_csi_extra" {
  name        = "${var.project_name}-ebs-csi-extra-policy"
  description = "Explicit permissions for EBS CSI attachment"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateVolume",
          "ec2:DeleteVolume",
          "ec2:DescribeVolumes",
          "ec2:DescribeInstances",
          "ec2:DescribeVolumesModifications",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:CreateSnapshot",
          "ec2:DeleteSnapshot",
          "ec2:DescribeSnapshots"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = [
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:snapshot/*",
          "arn:aws:ec2:*:*:instance/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi_extra_attach" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = aws_iam_policy.ebs_csi_extra.arn
}