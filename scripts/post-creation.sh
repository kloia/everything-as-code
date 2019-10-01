rm -rf ~/.kube/kloia
aws eks --region $REGION update-kubeconfig --name $CLUSTER --kubeconfig ~/.kube/kloia --alias kloia --profile kloia
export KUBECONFIG=~/.kube/kloia

if kubectl get serviceaccount tiller --namespace kube-system; then
  echo 'Tiller service account already found'
else
  kubectl create serviceaccount --namespace kube-system tiller
  kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
  helm init --service-account tiller
fi

if kubectl get ns vote; then
  echo 'Namespace already found'
else
  kubectl create ns vote
fi

if kubectl get secret aws-registry -n vote; then
  echo 'Secret already found'
else
  DOCKER_REGISTRY_SERVER=https://${AWS_ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com
  DOCKER_USER=AWS
  DOCKER_PASSWORD=`aws ecr get-login --region ${REGION} --registry-ids ${AWS_ACCOUNT} | cut -d' ' -f6`

  kubectl create -n vote secret docker-registry aws-registry \
    --docker-server=$DOCKER_REGISTRY_SERVER \
    --docker-username=$DOCKER_USER \
    --docker-password=$DOCKER_PASSWORD \
    --docker-email=no@email.local
fi
