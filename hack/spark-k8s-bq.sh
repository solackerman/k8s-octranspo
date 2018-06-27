export PROJECT=$(gcloud info --format='value(config.project)')
bq mk --project_id $PROJECT spark_on_k8s_manual

export PROJECT=$(gcloud info --format='value(config.project)')
bq query --project $PROJECT --replace          --destination_table spark_on_k8s_manual.go_files     'SELECT id, repo_name, path FROM
  [bigquery-public-data:github_repos.sample_files]
       WHERE RIGHT(path, 3) = ".go"'

export PROJECT=$(gcloud info --format='value(config.project)')
bq query --project $PROJECT 'SELECT sample_repo_name as
  repo_name, SUBSTR(content, 0, 10) FROM
  [bigquery-public-data:github_repos.sample_contents] WHERE id IN
  (SELECT id FROM spark_on_k8s_manual.go_files)'

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

sudo apt-get install -y maven
mvn clean package

export PROJECT=$(gcloud info --format='value(config.project)')
gsutil mb gs://$PROJECT-spark-on-k8s
gsutil cp target/github-insights-1.0-SNAPSHOT-jar-with-dependencies.jar                gs://$PROJECT-spark-on-k8s/jars/

bq mk --project_id $PROJECT spark_on_k8s
wget https://dist.apache.org/repos/dist/release/spark/spark-2.3.0/spark-2.3.0-bin-hadoop2.7.tgz
tar xvf spark-2.3.0-bin-hadoop2.7.tgz
cd spark-2.3.0-bin-hadoop2.7
cat > properties << EOF
spark.app.name  github-insights
spark.kubernetes.namespace default
spark.kubernetes.driverEnv.GCS_PROJECT_ID $PROJECT
spark.kubernetes.driverEnv.GOOGLE_APPLICATION_CREDENTIALS /mnt/secrets/spark-sa.json
spark.kubernetes.container.image gcr.io/cloud-solutions-images/spark:v2.3.0-gcs
spark.kubernetes.driver.secrets.spark-sa  /mnt/secrets
spark.kubernetes.executor.secrets.spark-sa /mnt/secrets
spark.driver.cores 0.1
spark.executor.instances 3
spark.executor.cores 1
spark.executor.memory 512m
spark.executorEnv.GCS_PROJECT_ID    $PROJECT
spark.executorEnv.GOOGLE_APPLICATION_CREDENTIALS /mnt/secrets/spark-sa.json
spark.hadoop.google.cloud.auth.service.account.enable true
spark.hadoop.google.cloud.auth.service.account.json.keyfile /mnt/secrets/spark-sa.json
spark.hadoop.fs.gs.project.id $PROJECT
spark.hadoop.fs.gs.system.bucket $PROJECT-spark-on-k8s
EOF

export KUBERNETES_MASTER_IP=$(gcloud container clusters list --filter name=spark-on-gke --format='value(MASTER_IP)')
bin/spark-submit \
    --properties-file properties \
    --deploy-mode cluster \
    --class spark.bigquery.example.github.NeedingHelpGoPackageFinder \
    --master k8s://https://$KUBERNETES_MASTER_IP:443 \
    --jars http://central.maven.org/maven2/com/databricks/spark-avro_2.11/4.0.0/spark-avro_2.11-4.0.0.jar \
    gs://$PROJECT-spark-on-k8s/jars/github-insights-1.0-SNAPSHOT-jar-with-dependencies.jar \
    $PROJECT spark_on_k8s $PROJECT-spark-on-k8s --usesample
