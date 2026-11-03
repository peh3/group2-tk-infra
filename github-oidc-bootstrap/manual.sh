aws secretsmanager put-secret-value \
  --secret-id "group2-tk/argocd/github-pat" \
  --secret-string '{"username":"peh3","token":"ghp_yourActualTokenHere"}' \
  --region ap-southeast-1