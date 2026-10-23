#!/bin/bash
# One-time setup for cloud-sim-runs, run by a person in AWS CloudShell (or anywhere the AWS CLI is signed in to the
# account as an administrator).
#
#   bash cloudshell_setup.sh <github-owner> <github-repo> [name]
#
# Creates, skipping anything that already exists:
#   1. the GitHub Actions OIDC identity provider;
#   2. the role <name>-github, assumable only by workflows on a branch of <github-owner>/<github-repo>;
#   3. the Terraform state bucket <name>-tfstate-<account> and the lock table <name>-tf-locks.
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "usage: bash cloudshell_setup.sh <github-owner> <github-repo> [name, default simruns]" >&2
  exit 2
fi
OWNER="$1"
REPO="$2"
NAME="${3:-simruns}"
REGION="${AWS_REGION:-$(aws configure get region || true)}"
REGION="${REGION:-us-east-1}"

echo "$NAME" | grep -Eq '^[a-z][a-z0-9-]{0,19}$' || { echo "name must match [a-z][a-z0-9-]{0,19}: $NAME" >&2; exit 2; }

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
echo "account $ACCOUNT, region $REGION, repository $OWNER/$REPO, name $NAME"

# 1. The OIDC provider. AWS no longer checks the thumbprint for GitHub's issuer, but older CLIs require one.
PROVIDER_ARN="arn:aws:iam::$ACCOUNT:oidc-provider/token.actions.githubusercontent.com"
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$PROVIDER_ARN" >/dev/null 2>&1; then
  echo "OIDC provider: already there"
else
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 >/dev/null
  echo "OIDC provider: created"
fi

# 2. The role. GitHub's token subject is usually repo:<owner>/<repo>:ref:refs/heads/<branch>, but some accounts
# send repo:<owner>@<owner id>/<repo>@<repo id>:ref:... instead (seen in CloudTrail in 2026). Both are allowed. The
# ids are public for a public repository; for a private one the lookup fails and only the plain form is used.
IDS=$(curl -fsS "https://api.github.com/repos/$OWNER/$REPO" 2>/dev/null \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["owner"]["id"], d["id"])' 2>/dev/null || true)
SUBS="\"repo:$OWNER/$REPO:ref:refs/heads/*\""
if [ -n "$IDS" ]; then
  set -- $IDS
  SUBS="$SUBS, \"repo:$OWNER@$1/$REPO@$2:ref:refs/heads/*\""
fi

ROLE="$NAME-github"
TRUST=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "GithubActionsFromOneRepository",
    "Effect": "Allow",
    "Principal": { "Federated": "$PROVIDER_ARN" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike": { "token.actions.githubusercontent.com:sub": [ $SUBS ] }
    }
  }]
}
EOF
)
if aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  aws iam update-assume-role-policy --role-name "$ROLE" --policy-document "$TRUST"
  echo "role $ROLE: already there, trust policy refreshed"
else
  aws iam create-role --role-name "$ROLE" --assume-role-policy-document "$TRUST" \
    --description "GitHub Actions for $OWNER/$REPO (cloud-sim-runs)" >/dev/null
  echo "role $ROLE: created"
fi
aws iam attach-role-policy --role-name "$ROLE" --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# 3. Terraform state.
BUCKET="$NAME-tfstate-$ACCOUNT"
if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  echo "state bucket $BUCKET: already there"
else
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
  fi
  echo "state bucket $BUCKET: created"
fi
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

TABLE="$NAME-tf-locks"
if aws dynamodb describe-table --table-name "$TABLE" --region "$REGION" >/dev/null 2>&1; then
  echo "lock table $TABLE: already there"
else
  aws dynamodb create-table --table-name "$TABLE" --region "$REGION" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST >/dev/null
  echo "lock table $TABLE: created"
fi

echo
echo "Done. Set these repository variables (GitHub > Settings > Secrets and variables > Actions > Variables):"
echo "  AWS_ACCOUNT_ID = $ACCOUNT"
[ "$REGION" != "us-east-1" ] && echo "  AWS_REGION     = $REGION"
[ "$NAME" != "simruns" ] && echo "  SIM_NAME       = $NAME"
exit 0
