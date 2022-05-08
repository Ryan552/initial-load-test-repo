#vars
PROJECT="rglynn01-40127817"
REGION=us-central1
ZONE=${REGION}-b
CLUSTER=gke-load-test
TARGET="34.88.173.43:8080"
SCOPE="https://www.googleapis.com/auth/cloud-platform"

#set project name
gcloud config set project $PROJECT

#set cluster zone
gcloud config set compute/zone ${ZONE}

#wait for background setup processes to finish before proceeding
wait

#create cluster, this may take several minutes
gcloud container clusters create $CLUSTER \
   --zone $ZONE \
   --scopes $SCOPE \
   --enable-autoscaling --min-nodes "3" --max-nodes "10" \
   --scopes=logging-write,storage-ro \
   --addons HorizontalPodAutoscaling,HttpLoadBalancing

#wait for cluster to be created
wait

#connect to cluster
gcloud container clusters get-credentials $CLUSTER \
   --zone $ZONE \
   --project $PROJECT

#wait for connection to cluster
wait

#build docker image for locust application
gcloud builds submit \
    --tag gcr.io/$PROJECT/locust-tasks:latest docker-image

#wait for the docker image to be built
wait

#check the docker container is built correctly by printing to screen
gcloud container images list | grep locust-tasks

#wait for docker image printout
wait

#change TARGET_HOST and PROJECT_ID to the $TARGET and $PROJECT environment variables
sed -i -e "s/\[PROJECT_ID\]/$PROJECT/g" kubernetes-config/locust-master-controller.yaml
sed -i -e "s/\[PROJECT_ID\]/$PROJECT/g" kubernetes-config/locust-worker-controller.yaml
sed -i -e "s/\[TARGET_HOST\]/$TARGET/g" kubernetes-config/locust-master-controller.yaml
sed -i -e "s/\[TARGET_HOST\]/$TARGET/g" kubernetes-config/locust-worker-controller.yaml

#wait for the kubernetes-config files to be edited
wait

#deploy the master node on the kubernetes cluster
kubectl apply -f kubernetes-config/locust-master-controller.yaml
kubectl apply -f kubernetes-config/locust-master-service.yaml
kubectl apply -f kubernetes-config/locust-worker-controller.yaml

#wait for the master node to be deployed on the cluster
wait

#verify the services have been set up
kubectl get services

echo "waiting for an external IP address to be assigned"

#set the $EXTERNAL_IP environment variable
EXTERNAL_IP=$(kubectl get svc locust-master -o jsonpath="{.status.loadBalancer.ingress[0].ip}")

#loop to check every second if the external IP address has been assigned
while [ -z $EXTERNAL_IP ]; do EXTERNAL_IP=$(kubectl get svc locust-master -o jsonpath="{.status.loadBalancer.ingress[0].ip}"); sleep 1; done

echo "The external IP for the master has been assigned as: $EXTERNAL_IP"

echo "Open the IP Address: http://$EXTERNAL_IP:8089 on your browser to see the locust hmi"
echo "you may have to wait for the worker nodes to finish deployment and connect to the master node"
