rm -rf ~/.kube/kloia
aws eks --region $REGION update-kubeconfig --name $CLUSTER --kubeconfig ~/.kube/kloia --profile kloia
export KUBECONFIG=~/.kube/kloia

# Install Helm
kubectl create serviceaccount --namespace kube-system tiller
kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
helm init --service-account tiller

# Create ECR Credentials Secret
DOCKER_REGISTRY_SERVER=https://${AWS_ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com
DOCKER_USER=AWS
DOCKER_PASSWORD=`aws ecr get-login --region ${REGION} --registry-ids ${AWS_ACCOUNT} | cut -d' ' -f6`

kubectl delete -n vote secret aws-registry || true
kubectl create -n vote secret docker-registry aws-registry \
  --docker-server=$DOCKER_REGISTRY_SERVER \
  --docker-username=$DOCKER_USER \
  --docker-password=$DOCKER_PASSWORD \
  --docker-email=no@email.local
