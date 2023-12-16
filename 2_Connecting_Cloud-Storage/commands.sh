############################################
# INITIALIZE LAB PARAMETERS AND VARIABLES  #
############################################
CLIENT_IP="10.10.10.10" # Change this line
LAB_ENV_NAME="lab-emr-cluster"
LAB_STACK_NAME="${LAB_ENV_NAME}-stack"
LAB_KEY_NAME="${LAB_ENV_NAME}-keypair"
LAB_KEY_FILE="${LAB_KEY_NAME}.pem"
CLOUD9_PRIVATE_IP=`hostname -i`
BUCKET_NAME="s3-dle-`uuidgen`"

############################################
# CREATE LAB INFRASTRUCTURE USING AWS CLI  #
############################################
aws configure set region us-east-1
export AWS_SHARED_CREDENTIALS_FILE=/home/ec2-user/.aws/credentials

CIDR_SUFFIX=
if [ "${CLIENT_IP}" = "0.0.0.0" ]; then
    CIDR_SUFFIX="/0"
else
    CIDR_SUFFIX="/32"
fi

aws ec2 create-key-pair \
    --key-name "${LAB_KEY_NAME}" \
    --query 'KeyMaterial' \
    --output text > "${LAB_KEY_FILE}"

chmod 400 "${LAB_KEY_FILE}" #change permissions

aws cloudformation deploy \
  --template-file ./template.json \
  --stack-name "lab-emr-cluster-stack" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    Name="${LAB_ENV_NAME}" \
    BucketName="${BUCKET_NAME}" \
    InstanceType=m4.large \
    ClientIP="${CLIENT_IP}${CIDR_SUFFIX}" \
    Cloud9IP="${CLOUD9_PRIVATE_IP}/32" \
    BucketName="${BUCKET_NAME}" \
    InstanceCount=2 \
    KeyPairName="${LAB_KEY_NAME}" \
    ReleaseLabel="emr-5.32.0" \
    EbsRootVolumeSize=32

############################################
# CONNECT TO EMR MASTER NODE               #
############################################
LAB_CLUSTER_ID=`aws emr list-clusters --query "Clusters[?Name=='${LAB_ENV_NAME}'].Id | [0]" --output text`
aws emr wait cluster-running --cluster-id ${LAB_CLUSTER_ID}
LAB_EMR_MASTER_PUBLIC_HOST=`aws emr describe-cluster --cluster-id ${LAB_CLUSTER_ID} --query Cluster.MasterPublicDnsName --output text`

ssh -i "${LAB_KEY_FILE}" "hadoop@${LAB_EMR_MASTER_PUBLIC_HOST}"

############################################
# PySpark import from AWS Open Data        #
############################################

pyspark

noaa_actuals = spark.read.option("header", True).csv('s3://noaa-gsod-pds/2022/*')
noaa_actuals_output = noaa_actuals.coalesce(32)

noaa_actuals_output.write \
  .format('parquet') \
  .mode('overwrite') \
  .save('s3://bucket_name/noaa_surface_summary/2022') # Replace bucket_name with your S3 bucket name
  
noaa_actuals_output.write \
  .format('parquet') \
  .mode('overwrite') \
  .save('/user/hadoop/noaa_surface_summary/2022')
  
noaa_actuals.show(10)
print(f'2022 weather observations: {noaa_actuals.count()}')

noaa_actuals.createOrReplaceTempView('noaa_actuals')

avg_high = spark.sql("SELECT AVG(MAX) FROM noaa_actuals")
avg_high.show()

avg_high.write \
  .format('csv') \
  .mode('overwrite') \
  .save('/user/hadoop/noaa_aggregates/2022/agg/avg_high_tmp')
  
exit()

############################################
# ACCESS FILES IN HDFS                     #
############################################

hdfs dfs -ls /user/hadoop/noaa_surface_summary # Check imported data in HDFS
hdfs dfs -ls /user/hadoop/noaa_surface_summary/2022/agg/avg_high_tmp # Check imported data in HDFS
hdfs dfs -cat /user/hadoop/noaa_aggregates/2022/agg/avg_high_tmp/*.csv # Print file to console

exit
############################################
# DELETE LAB RESOURCES                     #
############################################
aws cloudformation delete-stack --stack-name "lab-emr-cluster-stack"
aws ec2 delete-key-pair --key-name "${LAB_KEY_NAME}"
aws cloudformation wait stack-delete-complete --stack-name "lab-emr-cluster-stack"  