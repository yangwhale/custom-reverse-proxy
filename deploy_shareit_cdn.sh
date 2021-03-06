#!/bin/bash

# Nginx conf settings
# For basic CDN deployment with nginx_basic_proxy.conf, only CDN_CACHE_EXPIRE and ORIGIN_URL need to be updated before deploying.
export NGINX_TEMPLATE=https://raw.githubusercontent.com/yangwhale/custom-reverse-proxy/master/openresty/nginx/conf/nginx_basic_proxy.conf
export CDN_CACHE_EXPIRE=2592000
export ORIGIN_URL=http://d2f89xs4on71s8.cloudfront.net

# gcloud command settings
# Update to your own choice of naming and region
export PROJECT_ID=project-for-shareit
export BASE_INSTANCE_NAME=google-cdn-proxy-base
export IMAGE_NAME=google-cdn-proxy-base-image
export INSTANCE_TEMPLATE_NAME=google-cdn-proxy-ig-temp-v1
export HEALTHCHECK_NAME=healthckeck-google-cdn-proxy
export INSTANCE_GROUP_NAME=ig-google-cdn-proxy
export BACKEND_NAME=bs-google-cdn-proxy
export URLMAP_NAME=glb-google-cdn
export TARGET_PROXY_NAME=target-google-cdn-proxy
export FORWARD_RULE_NAME=forward-rule-google-cdn-proxy
export REGION=asia-southeast1
export ZONE=asia-southeast1-a
export INSTANCE_GROUP_ZONES=asia-southeast1-a,asia-southeast1-b,asia-southeast1-c

# 1. Create base VM, with openresty installed
gcloud beta compute --project=$PROJECT_ID instances create $BASE_INSTANCE_NAME --zone=$ZONE --machine-type=n1-standard-1 --subnet=default --network-tier=PREMIUM --maintenance-policy=MIGRATE --tags=cdn-proxy,http-server,https-server --image=ubuntu-1804-bionic-v20200129a --image-project=ubuntu-os-cloud --boot-disk-size=10GB --boot-disk-type=pd-standard --boot-disk-device-name=$BASE_INSTANCE_NAME --reservation-affinity=any --service-account=compute@chris-test-demo.iam.gserviceaccount.com --metadata=startup-script=wget\ -O\ -\ https://raw.githubusercontent.com/yangwhale/custom-reverse-proxy/master/openresty/gce_startup.sh\ \|\ bash
sleep 60
	
# 2. Create custom Image
gcloud compute images create $IMAGE_NAME --project=$PROJECT_ID --source-disk=$BASE_INSTANCE_NAME --source-disk-zone=$ZONE --storage-location=$REGION --force
	
# 3. Create instance template

gcloud beta compute --project=$PROJECT_ID instance-templates create $INSTANCE_TEMPLATE_NAME --machine-type=n1-standard-4 --network-tier=PREMIUM --maintenance-policy=MIGRATE --tags=cdn-proxy,http-server,https-server --image=$IMAGE_NAME --image-project=$PROJECT_ID --boot-disk-size=30GB --boot-disk-type=pd-standard --boot-disk-device-name=$INSTANCE_TEMPLATE_NAME --reservation-affinity=any --service-account=compute@chris-test-demo.iam.gserviceaccount.com --metadata=startup-script="#! /bin/bash
export ORIGIN_URL=${ORIGIN_URL}
export CDN_CACHE_EXPIRE=${CDN_CACHE_EXPIRE}
wget $NGINX_TEMPLATE --output-document=nginx.conf
cp /usr/local/openresty/nginx/conf/nginx.conf /usr/local/openresty/nginx/conf/nginx_def.conf
envsubst '\${ORIGIN_URL} \${CDN_CACHE_EXPIRE}' < ./nginx.conf > /usr/local/openresty/nginx/conf/nginx.conf
systemctl restart openresty"

# 4. Create Instance Group

gcloud compute health-checks create http $HEALTHCHECK_NAME --project=$PROJECT_ID --port=80 --request-path=/gcphc --proxy-header=NONE --check-interval=5 --timeout=5 --unhealthy-threshold=2 --healthy-threshold=2

gcloud beta compute --project=$PROJECT_ID instance-groups managed create $INSTANCE_GROUP_NAME --base-instance-name=$INSTANCE_GROUP_NAME --template=$INSTANCE_TEMPLATE_NAME --size=1 --zones=$INSTANCE_GROUP_ZONES --instance-redistribution-type=PROACTIVE --health-check=$HEALTHCHECK_NAME --initial-delay=60

gcloud beta compute --project "$PROJECT_ID" instance-groups managed set-autoscaling "$INSTANCE_GROUP_NAME" --region "$REGION" --cool-down-period "60" --max-num-replicas "10" --min-num-replicas "2" --target-cpu-utilization "0.6" --mode "on"


# 5. Create LB

gcloud compute --project=$PROJECT_ID backend-services create $BACKEND_NAME \
--protocol HTTP \
--health-checks $HEALTHCHECK_NAME \
--global \
--enable-cdn \
--timeout=60

gcloud compute --project=$PROJECT_ID backend-services add-backend $BACKEND_NAME \
--balancing-mode=UTILIZATION \
--max-utilization=0.8 \
--capacity-scaler=1 \
--instance-group=$INSTANCE_GROUP_NAME \
--instance-group-region=$REGION \
--global

gcloud compute --project=$PROJECT_ID url-maps create $URLMAP_NAME \
--default-service $BACKEND_NAME

gcloud compute --project=$PROJECT_ID target-http-proxies create $TARGET_PROXY_NAME \
--url-map $URLMAP_NAME 

gcloud compute --project=$PROJECT_ID forwarding-rules create $FORWARD_RULE_NAME \
--global \
--target-http-proxy=$TARGET_PROXY_NAME \
--ports=80
