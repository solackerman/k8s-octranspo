# bin/sh

brew install argoproj/tap/argo
argo install
kubectl create clusterrolebinding sol-cluster-admin-binding --clusterrole=cluster-admin --user=sol.ackerman@shopify.com
kubectl create rolebinding default-admin --clusterrole=admin --serviceaccount=default:default

kubectl create -f argo/manifest/secret.yaml
# Create a gcs bucket (argo-octranspo-190317),
# and make it s3 compatible as described here: https://github.com/argoproj/argo/blob/master/ARTIFACT_REPO.md
# then, update the workflow-controller-configmap. This is what I really did:
# kubectl edit configmap workflow-controller-configmap -n kube-system
# which is equivalent to:
kubectl replace configmap workflow-controller-configmap -n kube-system -f argo/manifest/config-map/workflow-controller-configmap.yaml
kubectl patch svc argo-ui -n kube-system -p '{"spec": {"type": "LoadBalancer"}}'

# install spark-k8
kubectl apply -f spark-on-k8s-operator/manifest/

# when using argo and spark, this fixes the following error:
# Error from server (Forbidden): error when creating "/tmp/manifest.yaml": sparkapplications.sparkoperator.k8s.io is forbidden: User "system:serviceaccount:default:default" cannot create sparkapplications.sparkoperator.k8s.io in the namespace "default": Unknown user "system:serviceaccount:default:default"
kubectl create clusterrolebinding default-cluster-admin-binding --clusterrole=cluster-admin --serviceaccount=default:default


# stuff for getting spark working with BQ and GCS
gcloud iam service-accounts create spark-bq --display-name spark-bq
export SA_EMAIL=$(gcloud iam service-accounts list --filter="displayName:spark-bq" --format='value(email)')
export PROJECT=$(gcloud info --format='value(config.project)')

gcloud projects add-iam-policy-binding $PROJECT --member serviceAccount:$SA_EMAIL --role roles/storage.admin
gcloud projects add-iam-policy-binding $PROJECT --member serviceAccount:$SA_EMAIL --role roles/bigquery.dataOwner
gcloud projects add-iam-policy-binding $PROJECT --member serviceAccount:$SA_EMAIL --role roles/bigquery.jobUser
gcloud iam service-accounts keys create spark-sa.json --iam-account $SA_EMAIL
kubectl create secret generic spark-sa --from-file=spark-sa.json

kubectl create clusterrolebinding user-admin-binding --clusterrole=cluster-admin --user=$(gcloud config get-value account)
kubectl create clusterrolebinding --clusterrole=cluster-admin --serviceaccount=default:default spark-admin
