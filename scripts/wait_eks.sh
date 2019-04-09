#!/usr/bin/env bash

unset $eks_endpoint

while true
do
  eks_endpoint=$(aws eks describe-cluster --name $PROJECT_NAME --profile $PROFILE_NAME --region $REGION_NAME 2>/dev/null | jq '.cluster.endpoint' | sed 's~http[s]*://~~g'| sed 's/"//g')
  if [[ $eks_endpoint = *eks.amazonaws.com* ]]; then
    echo "eks endpoint= $eks_endpoint"
    nc -w3 -z $eks_endpoint 443 -vv
    break
  fi
  echo "waiting for eks endpoint"
  sleep 3
done
