#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Rewires every Lambda in a stack to the newest version of a layer.
#
# Only needed after "sam sync --code" publishes a new layer version, because that
# path talks to the Lambda APIs directly and leaves functions pointing at the old
# version. The regular "sam deploy" path needs nothing: !Ref ServerlessSaaSLayers
# lives in the same template as the functions, so CloudFormation rewires them.

set -uo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: update_lambda_layer.sh <stack-name> <layer-name>" >&2
  exit 1
fi

STACK_NAME=$1
LAYER_NAME=$2

# Walking a stack tree and reading every function's config throttles easily.
# Standard retry mode backs off on TooManyRequestsException; legacy mode does not.
export AWS_RETRY_MODE=standard
export AWS_MAX_ATTEMPTS=10

# Exact name match: serverless-saas-dependencies must never resolve to
# serverless-saas-dependencies-pooled or serverless-saas-dependencies-<tenantId>.
# max_by rather than [0] so the result does not depend on API ordering, and no
# --max-items so the CLI does not append a pagination token to the output.
if ! TARGET_ARN=$(aws lambda list-layer-versions --layer-name "$LAYER_NAME" \
  --query "max_by(LayerVersions, &Version).LayerVersionArn" --output text | tr -d '\r'); then
  echo "ERROR: could not list versions of layer '$LAYER_NAME'" >&2
  exit 1
fi

if [[ -z "$TARGET_ARN" || "$TARGET_ARN" == "None" ]]; then
  echo "ERROR: layer '$LAYER_NAME' has no published versions" >&2
  exit 1
fi

echo "Target layer version: $TARGET_ARN"

# Collect Lambda functions from the stack and all its nested stacks. Recursing
# rather than assuming a fixed child name, because pooled/silo tenant stacks
# declare their functions in the root template.
collect_functions() {
  local stack=$1 resources
  # A nested stack's PhysicalResourceId is a full ARN, which DescribeStackResources
  # rejects for exceeding the 128-character stack-name limit. Reduce it to the name.
  if [[ "$stack" == arn:* ]]; then
    stack=${stack#*:stack/}
    stack=${stack%%/*}
  fi
  # tr -d '\r': the AWS CLI emits CRLF on Windows, and a trailing carriage return
  # makes every resource name fail service-side validation.
  if ! resources=$(aws cloudformation describe-stack-resources --stack-name "$stack" \
    --query "StackResources[?ResourceType=='AWS::Lambda::Function' || ResourceType=='AWS::CloudFormation::Stack'].[ResourceType,PhysicalResourceId]" \
    --output text </dev/null | tr -d '\r'); then
    echo "ERROR: could not describe resources of stack '$stack'" >&2
    return 1
  fi

  while IFS=$'\t' read -r type physical_id; do
    [[ -z "$type" ]] && continue
    if [[ "$type" == "AWS::Lambda::Function" ]]; then
      printf '%s\n' "$physical_id"
    else
      collect_functions "$physical_id" || return 1
    fi
  done <<<"$resources"
}

if ! FUNCTIONS=$(collect_functions "$STACK_NAME" | sort -u); then
  exit 1
fi

if [[ -z "$FUNCTIONS" ]]; then
  echo "ERROR: no Lambda functions found in stack '$STACK_NAME'" >&2
  exit 1
fi

updated=0
current_count=0
no_layer=0
failed=0

while read -r fn; do
  [[ -z "$fn" ]] && continue

  # Never silence this: a throttled or failed read must not look like "no layers".
  if ! attached=$(aws lambda get-function-configuration --function-name "$fn" \
    --query "Layers[].Arn" --output text </dev/null | tr -d '\r'); then
    echo "  ERROR: could not read configuration of $fn" >&2
    failed=$((failed + 1))
    continue
  fi

  if [[ "$attached" == *"$TARGET_ARN"* ]]; then
    current_count=$((current_count + 1))
    continue
  fi

  # --layers replaces the whole array, so preserve every other layer
  # (notably LambdaInsightsExtension, attached via the template's Globals).
  new_layers=()
  uses_target_layer=false
  for arn in $attached; do
    if [[ "$arn" == *":layer:${LAYER_NAME}:"* ]]; then
      new_layers+=("$TARGET_ARN")
      uses_target_layer=true
    else
      new_layers+=("$arn")
    fi
  done

  if [[ "$uses_target_layer" == false ]]; then
    no_layer=$((no_layer + 1))
    continue
  fi

  echo "  update $fn"
  if ! aws lambda update-function-configuration --function-name "$fn" \
    --layers "${new_layers[@]}" </dev/null >/dev/null; then
    echo "  ERROR: failed to update $fn" >&2
    failed=$((failed + 1))
    continue
  fi

  # Consecutive updates to the same function race unless we wait.
  if ! aws lambda wait function-updated-v2 --function-name "$fn" </dev/null; then
    echo "  ERROR: $fn did not reach Successful state" >&2
    failed=$((failed + 1))
    continue
  fi
  updated=$((updated + 1))
done <<<"$FUNCTIONS"

echo "Layer rewire complete: $updated updated, $current_count already current, $no_layer not using '$LAYER_NAME', $failed failed"
[[ $failed -eq 0 ]] || exit 1
