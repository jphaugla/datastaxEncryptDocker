# DataStax Encrytion using Docker Compose

## About

This github covers setting up encryption for DataStax.  Two main docker containers are used:   DataStax Server and DataStax opscenter.


The DataStax images are well documented at this github location  [https://github.com/datastax/docker-images/](https://github.com/datastax/docker-images/)



## Getting Started
1. Prepare Docker environment
2. Pull this github into a directory  `git clone https://github.com/jphaugla/datastaxEncryptDocker.git`
3. Follow notes from DataStax Docker github to pull the needed DataStax images.  Directions are here:  [https://github.com/datastax/docker-images/#datastax-platform-overview]().  Don't get too bogged down here as the docker-compose.yaml handles most everything.
4. Open terminal, then: `docker-compose up -d`
5. Verify DataStax is working for both hosts: (may need to wait a minute for DSE to start on each node)
```bash
docker exec dse cqlsh dse -u cassandra -p cassandra -e "desc keyspaces";
```
```bash
docker exec dse2 cqlsh dse2 -u cassandra -p cassandra -e "desc keyspaces"
```
6. Add demo tables and keyspace for later DSE Search testing:
```bash
docker exec dse bash -c '/opt/dse/demos/solr_stress/resources/schema/create-schema.sh'
```
7. Add Data
 ```bash
docker exec dse /opt/dse/demos/solr_stress/run-benchmark.sh --url=http://dse:8983 --test-data=./resources/testCqlWrite.txt --loops 110000
```
8. Also note, in the home directory for the github repository directory the docker volumes should be created as subdirectories.  To manipulate the dse.yaml file, the local conf subdirectory will be used.  The other dse directories are logs, cache and data.  Additionally, I added a confy directory to hold the encryption files and the system_key_directory

## Set up Encryption

The general instructions for starting the DSE Transparent Data Encryption is here:
https://docs.datastax.com/en/dse/5.1/dse-admin/datastax_enterprise/security/secEncryptEnable.html

This tutorial provides specific commands for this environment, so it shouldn't be necessary to refer to the docs, but they're a handy reference if something goes awry.  
1. Get the JAVA_HOME of the DataStax servers by running:
```bash
export DSE_JAVA=$(docker exec dse bash -c 'echo "$JAVA_HOME"')
```
2. To enable strong encryption using Java there is a requirement for adding additional encryption libraries to the stock Java install. These assume you comply with US laws around encryption strength for export.
   1. Download the files from Oracle’s website to github home directory:
[http://www.oracle.com/technetwork/java/javase/downloads/jce8-download-2133166.html](http://www.oracle.com/technetwork/java/javase/downloads/jce8-download-2133166.html)
   2. currently this file is downloading as a folder instead of a zip file.  If it is a zip file, unzip the archive file using:  `unzip jce_policy-8.zip`    
   3. Upload the archive file to all DSE servers using JAVA_HOME environment variable from step 1 
```bash
docker cp UnlimitedJCEPolicyJDK8/US_export_policy.jar dse:/$DSE_JAVA/jre/lib/security;
``` 
```bash
docker cp UnlimitedJCEPolicyJDK8/local_policy.jar dse:/$DSE_JAVA/jre/lib/security;
``` 
```bash
docker cp UnlimitedJCEPolicyJDK8/US_export_policy.jar dse2:/$DSE_JAVA/jre/lib/security;
``` 
```bash
docker cp UnlimitedJCEPolicyJDK8/local_policy.jar dse2:/$DSE_JAVA/jre/lib/security
``` 

2. Create certificates on each node by creating a keystore and exporting the certificate.  In this example we will create /usr/share/dse/conf and store the key and trust stores in that directory. 
```bash
docker exec dse $DSE_JAVA/bin/keytool -genkey -keyalg RSA -alias dse -keystore keystore.dse -storepass cassandra -keypass cassandra -dname "CN=dse, OU=None, O=None, L=None, C=None";
```
```bash
docker exec dse2 $DSE_JAVA/bin/keytool -genkey -keyalg RSA -alias dse2 -keystore keystore.dse2 -storepass cassandra -keypass cassandra -dname "CN=dse2, OU=None, O=None, L=None, C=None"
```

3. Export the certificate to be copied to other nodes from each node 
```bash
docker exec dse $DSE_JAVA/bin/keytool -export -alias dse -file dse.cer -keystore keystore.dse;
```
```bash
docker exec dse2 $DSE_JAVA/bin/keytool -export -alias dse2 -file dse2.cer -keystore keystore.dse2
```

4. Load the certificate into the trust store on each node
```bash
docker exec dse $DSE_JAVA/bin/keytool -import -v -trustcacerts -alias dse -file dse.cer -keystore truststore.dse -storepass cassandra -noprompt;
```
```bash
docker exec dse2 $DSE_JAVA/bin/keytool -import -v -trustcacerts -alias dse2 -file dse2.cer -keystore truststore.dse2 -storepass cassandra -noprompt
```

5. Get certificates in PKS format for cqlsh
```bash
docker exec dse $DSE_JAVA/bin/keytool -importkeystore -srckeystore keystore.dse -destkeystore dse.p12 -deststoretype PKCS12 -srcstorepass cassandra -deststorepass cassandra;
```
```bash
docker exec dse2 $DSE_JAVA/bin/keytool -importkeystore -srckeystore keystore.dse2 -destkeystore dse2.p12 -deststoretype PKCS12 -srcstorepass cassandra -deststorepass cassandra
```

6. Create a '.pem' file for cqlsh
```bash
docker exec dse openssl pkcs12 -in dse.p12 -nokeys -out dse.cer.pem -passin pass:cassandra;
```
```bash
docker exec dse openssl pkcs12 -in dse.p12 -nodes -nocerts -out dse.key.pem -passin pass:cassandra;
```
```bash
docker exec dse2 openssl pkcs12 -in dse2.p12 -nokeys -out dse2.cer.pem -passin pass:cassandra;
```
```bash
docker exec dse2 openssl pkcs12 -in dse2.p12 -nodes -nocerts -out dse2.key.pem -passin pass:cassandra
```

7. copy '.cer' files to local docker hosts
```bash
docker cp dse:/opt/dse/dse.cer .;
``` 
```bash
docker cp dse2:/opt/dse/dse2.cer .
```

8. copy '.cer' file to other host (so dse.cer to dse2 and dse2.cer to dse)
```bash
docker cp dse.cer dse2:/opt/dse;
```
```bash
docker cp dse2.cer dse:/opt/dse
```

9. load the '.cer' file to truststore
```bash
docker exec dse $DSE_JAVA/bin/keytool -import -v -trustcacerts -alias dse2 -file dse2.cer -keystore truststore.dse -storepass cassandra -noprompt;
```
```bash
docker exec dse2 $DSE_JAVA/bin/keytool -import -v -trustcacerts -alias dse -file dse.cer -keystore truststore.dse2 -storepass cassandra -noprompt
```

10. Copy all the key related files to a docker volume for container restart
```bash
docker exec dse bash -c "cp *dse* /etc/dse/conf";
```
```bash
docker exec dse2 bash -c "cp *dse* /etc/dse/conf"
```

## Configure DSE to use encryption

1. Generate DSE system key on each node
```bash
docker exec dse dsetool createsystemkey AES/ECB/PKCS5Padding 256 system_key;
```
```bash
docker exec dse2 dsetool createsystemkey AES/ECB/PKCS5Padding 256 system_key
```
2. Encrypt keystore and truststore password using dsetool.  First getting bash shell and then typing dsetool command.  Save each of these values for subsequent steps.  Manually type a password such as "cassandra" when prompted by dsetool
```bash
docker exec -i -t dse bash
```
```bash
dsetool encryptconfigvalue
```
```bash
docker exec -i -t dse2 bash
```
```bash
dsetool encryptconfigvalue
```
3. Either use existing provided dse.yaml command with encryption entries complete or go through the steps by getting a local copy of the dse.yaml file from the dse container.  
```bash
docker cp dse:/opt/dse/resources/dse/conf/dse.yaml .
```  
However, this existing dse.yaml is for 6.0.0 and may not work in subsequent versions.  Also provided in the github is a diff file call dse.yaml.diff
4. Edit local copy of the dse.yaml being extremely careful to maintain the correct spaces as the yaml is space aware.   Thankfully, any errors are obvious in /var/log/cassandra/system.log on startup failure 
```yaml
(~line 494):
config_encryption_active: true
```
```yaml
(~line 850):
system_info_encryption:
    enabled: true
    cipher_algorithm: AES
    secret_key_strength: 256
    chunk_length_kb: 64
    key_name: system_key
```     
5. Save this edited dse.yaml file to the conf subdirectory and to the conf2 directory.  It will be picked up on the next dse restart.  Simplest is just do `cp dse.yaml conf` and `cp dse.yaml conf2`For notes on this look here:  [https://github.com/datastax/docker-images/#using-the-dse-conf-volume](https://github.com/datastax/docker-images/#using-the-dse-conf-volume)
6. Make copy of the cassandra node for each node (don't mix these up).  
```bash
docker cp dse:/opt/dse/resources/cassandra/conf/cassandra.yaml conf;
```
```bash
docker cp dse2:/opt/dse/resources/cassandra/conf/cassandra.yaml conf2
```
7. Edit each cassandra.yaml file
 (~line 957)  the password comes from step 2 (use correct encrypted password for each node)
```
 server_encryption_options:
    internode_encryption: all
    keystore: /etc/dse/conf/keystore.dse
    keystore_password: ZyOPkOf0RgNDgTZkVK50DQ==
    truststore: /etc/dse/conf/truststore.dse
    truststore_password: ZyOPkOf0RgNDgTZkVK50DQ== 
``` 
(~line 972)  the password comes from step 2 (use correct encrypted password for each node)
```yaml  
 client_encryption_options:
    enabled: true
    optional: false
    keystore: /etc/dse/conf/keystore.dse
    keystore_password: ZyOPkOf0RgNDgTZkVK50DQ==
    require_client_auth: true
    truststore: /etc/dse/conf/truststore.dse
    truststore_password: ZyOPkOf0RgNDgTZkVK50DQ==
```  
8. Restart the dse docker container: `docker restart dse`
9. Repeat steps 7 and 8 for dse2  (remember, for dse2 the names are different; keystore.dse2, truststore.dse2
9. Configure cqlsh to work with encryption.  Use the cqlshrc files from the github for each node. 
```bash
docker cp cqlshrc dse:/opt/dse/.cassandra;
```
```bash
docker cp cqlshrc2 dse2:/opt/dse/.cassandra/cqlshrc
```
this is the file for doc purposes:
```bash
[connection]
hostname = dse
port = 9042
factory = cqlshlib.ssl.ssl_transport_factory
[ssl]
certfile = /etc/dse/conf/dse.cer.pem
validate = true
userkey = /etc/dse/conf/dse.key.pem
usercert = /etc/dse/conf/dse.cer.pem
```
10. Test cqlsh in each node by getting bash shell to node and using cqlsh

```bash
docker exec -it dse bash
```

```bash
cqlsh dse --ssl
```

```bash
docker exec -it dse2 bash
```

```bash
cqlsh dse2 --ssl
```

## Enable Transparent Data Encryption on a table.

1. Generate new encryption key
```bash
docker exec dse dsetool createsystemkey AES/ECB/PKCS5Padding 256 test_table_key;
```
2. copy encryption key to other node
```bash 
docker cp dse:/etc/dse/conf/test_table_key .;
```
```bash
docker cp test_table_key dse2:/etc/dse/conf
```
 
3. Alter table to turn on encryption
```bash
docker exec dse cqlsh dse --ssl -e "alter table demo.solr  WITH
compression = {
'sstable_compression': 'EncryptingSnappyCompressor',
'cipher_algorithm' : 'AES/ECB/PKCS5Padding',
'secret_key_strength' : 256,
'chunk_length_kb' : 128,
 'system_key_file':'test_table_key'
} 
"
```
4. Describe the table to verify encryption:

```bash
    docker exec dse cqlsh --ssl -e "desc demo.solr"    
```
5. upgrade the sstables to encrypt on each node.
```bash
 docker exec -it dse bash -c "nodetool upgradesstables -a";
```
```bash
 docker exec -it dse2 bash -c "nodetool upgradesstables -a"
```

## Enable SOLR encryption
1. turn encryption on the DSE Search 
```bash
docker exec -it dse cqlsh dse --ssl -e "alter search index config on demo.solr set directoryFactory = 'encrypted'";
```
```bash
docker exec -it dse cqlsh dse --ssl  -e "reload search index on demo.solr"
```
2.  restart for directoryFactory change
`docker-compose restart`
3.  rebuild the index
```bash 
docker exec -it dse cqlsh dse --ssl  -e "rebuild search index on demo.solr with options {deleteAll :true}"
```
4.  Copy relevant files off the image and use the `strings` command to ensure encryption
5. To generate more records with encryption turned on:
```bash
docker exec dse /opt/dse/demos/solr_stress/run-benchmark.sh --url=http://dse:8983 --test-data=./resources/testCqlWrite.txt --loops 110000 --cqlSSL --cqlKeystore=/etc/dse/conf/keystore.dse --cqlKeystorePassword=cassandra --cqlTruststore=/etc/dse/conf/truststore.dse --cqlTruststorePassword=cassandra
```
6. To use dse tool must add ssl parameters to dsetool call
```bash
docker exec dse bash -c "dsetool -ssl true --sslauth true --truststore-password cassandra --truststore-path /etc/dse/conf/truststore.dse --truststore-type jks --keystore-password cassandra --keystore-path /etc/dse/conf/keystore.dse --keystore-type jks get_core_config demo.solr"
```

## Conclusion

At this point, DSE is set up with encryption

##  Additional Notes/tips

* To get the IP address of the DataStax nodes:

```bash
export DSE_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' dse)
```
   and:
```bash
export DSE2_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' dse2)
```
* use `echo $DSE_IP` and `echo $DSE2_IP` to view

