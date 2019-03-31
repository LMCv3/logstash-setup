#!/bin/bash
# Set up Logstash for ElasticSearch setups
# TODO: Config to allow for lower memory usage

# Check to see if we are root
if [ "$(id -u)" != "0" ]; then
	echo "You'll need to be root for this, though..."
	exit 1
fi

echo -n "AWS Access Key ID: "
read $awskey
echo -n "AWS Secret Access Key: "
read $awssecret
echo -n "Default region name [us-east-1]: "
read $awsregion
echo -n "ElasticSearch endpoint URL (include https:// and / at the end): "
read $elastihost

# Default region, if not entered:
if [ -z "$awsregion" ]
then
	awsregion="us-east-1"
fi

# Add ElasticSearch Key and Logstash Repo
echo "Importing Logstash key & updating package list..."
wget -qO - https://packages.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
echo "deb https://packages.elastic.co/logstash/2.4/debian stable main" > /etc/apt/sources.list.d/logstash.list
apt-get update

# Install OpenJDK and Logstash
apt-get install openjdk-8-jdk logstash

# Install AWS ElasticSearch Plugin
echo "Installing AWS ElasticSearch Plugin..."
/opt/logstash/bin/logstash-plugin install logstash-output-amazon_es

# Get list of access files
accessarray=()
while IFS=  read -r -d $'\0'; do
	accessarray+=("$REPLY")
done < <(find /var/log/apache2 -name "access*.log" -print0)

# Get list of error files
errorarray=()
while IFS=  read -r -d $'\0'; do
	errorarray+=("$REPLY")
done < <(find /var/log/apache2 -name "error*.log" -print0)

# Build Logstash Config files
echo "input {" > /etc/logstash/conf.d/02-apache-input.conf
for accesslog in "${accessarray[@]}"
do
	echo " file {" >> /etc/logstash/conf.d/02-apache-input.conf
	echo "   path => [\"$accesslog\"]" >> /etc/logstash/conf.d/02-apache-input.conf
	echo "   type => \"apache_access\"" >> /etc/logstash/conf.d/02-apache-input.conf
	echo " }" >> /etc/logstash/conf.d/02-apache-input.conf
done
for errorlog in "${errorarray[@]}"
do
	echo " file {" >> /etc/logstash/conf.d/02-apache-input.conf
	echo "   path => [\"$errorlog\"]" >> /etc/logstash/conf.d/02-apache-input.conf
	echo "   type => \"apache_error\"" >> /etc/logstash/conf.d/02-apache-input.conf
	echo " }" >> /etc/logstash/conf.d/02-apache-input.conf
done

echo "}" >> /etc/logstash/conf.d/02-apache-input.conf
mv 10-apache-filter.conf /etc/logstash/conf.d/

# Build AWS cres conf file
echo "output {" > /etc/logstash/conf.d/20-apache-es.conf
echo " stdout {}" >> /etc/logstash/conf.d/20-apache-es.conf
echo " amazon_es {" >> /etc/logstash/conf.d/20-apache-es.conf
echo "   region => \"$awsregion\"" >> /etc/logstash/conf.d/20-apache-es.conf
echo "   index => \"apache-%{+YYYY.MM.dd}\"" >> /etc/logstash/conf.d/20-apache-es.conf
echo "   document_type => \"apache_logs\"" >> /etc/logstash/conf.d/20-apache-es.conf
echo "   hosts => [\"$elastihost\"]" >> /etc/logstash/conf.d/20-apache-es.conf
echo "   aws_access_key_id => '$awskey'" >> /etc/logstash/conf.d/20-apache-es.conf
echo "   aws_secret_access_key => '$awssecret'" >> /etc/logstash/conf.d/20-apache-es.conf
echo " }" >> /etc/logstash/conf.d/20-apache-es.conf
echo "}" >> /etc/logstash/conf.d/20-apache-es.conf

# Set a reasonable heap size
echo "Setting heap size to 256M-512M..."
echo "environment:
        - LS_JAVA_OPTS=-Xmx512M -Xms256M" > /etc/logstash/logstash.yml

# Restart logstash
echo "Setup finished! Restarting Logstash..."
service logstash stop
service logstash start
