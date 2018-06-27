build:
	docker build -t spark-gcs .

enter-container:
	docker run -it --entrypoint=/bin/bash spark-gcs:latest

push: build
	docker tag "spark-gcs:latest" "gcr.io/octranspo-190317/spark-gcs"
	docker push gcr.io/octranspo-190317/spark-gcs
