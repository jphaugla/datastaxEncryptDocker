# datastaxEncryptDocker

## About

This github covers setting up encryption for DataStax.  Two main docker containers are used:   DataStax Server and DataStax opscenter.


The DataStax images are well documented at this github location  [https://github.com/datastax/docker-images/]()



## Getting Started
1. Prepare Docker environment
2. Pull this github into a directory  `git clone https://github.com/jphaugla/datastaxEncryptDocker.git`
3. Follow notes from DataStax Docker github to pull the needed DataStax images.  Directions are here:  [https://github.com/datastax/docker-images/#datastax-platform-overview]().  Don't get too bogged down here.  The pull command is provided with this github in pull.sh. It is requried to have the docker login and subscription complete before running the pull.  The also included docker-compose.yaml handles most everything else.
4. Open terminal, then: `docker-compose up -d`
5. Verify DataStax is working for both hosts:
```
docker exec dse cqlsh -u cassandra -p cassandra -e "desc keyspaces";
```
```
docker exec dse2 cqlsh -u cassandra -p cassandra -e "desc keyspaces"
```
6. Add demo tables and keyspace for later DSE Search testing:
```
docker exec dse bash -c '/opt/dse/demos/solr_stress/resources/schema/create-schema.sh'
```
7. Add Data
 ```
docker exec dse /opt/dse/demos/solr_stress/run-benchmark.sh --test-data=./resources/testCqlWrite.txt --loops 110000
```
8. Also note, in the home directory for the github repository directory the docker volumes should be created as subdirectories.  To manipulate the dse.yaml file, the local conf subdirectory will be used.  The other dse directories are logs, cache and data.  Additionally, I added a confy directory to hold the encryption files and the system_key_directory

## Set up Encryption

The general instructions for starting the DSE Transparent Data Encryption is here:
https://docs.datastax.com/en/dse/5.1/dse-admin/datastax_enterprise/security/secEncryptEnable.html

This tutorial provides specific commands for this environment, so it shouldn't be necessary to refer to the docs, but they're a handy reference if something goes awry.  

1. Get the IP address and JAVA_HOME of the DataStax servers by running:
```
export DSE_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' dse)
```
```
export DSE_IP2=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' dse2)
export DSE_JAVA=$(docker exec dse bash -c 'echo "$JAVA_HOME"')
```
use `echo $DSE_IP` and `echo $DSE_IP2` and `echo $DSE_JAVA` to view

2. To enable strong encryption using Java there is a requirement for adding additional encryption libraries to the stock Java install. These assume you comply with US laws around encryption strength for export.
   1. Download the files from Oracle’s website to github home directory:
        	http://www.oracle.com/technetwork/java/javase/downloads/jce8-download-2133166.html
   2. unzip the archive file `unzip jce_policy-8.zip`    
   3. Upload the archive file to all DSE servers using JAVA_HOME environment variable from step 1 
```
docker cp UnlimitedJCEPolicyJDK8/US_export_policy.jar dse:/$DSE_JAVA/jre/lib/security;
``` 
```
docker cp UnlimitedJCEPolicyJDK8/local_policy.jar dse:/$DSE_JAVA/jre/lib/security;
``` 
```
docker cp UnlimitedJCEPolicyJDK8/US_export_policy.jar dse2:/$DSE_JAVA/jre/lib/security;
``` 
```
docker cp UnlimitedJCEPolicyJDK8/local_policy.jar dse2:/$DSE_JAVA/jre/lib/security
``` 

3. Create certificates on each node by creating a keystore and exporting the certificate.  In this example we will create /usr/share/dse/conf and store the key and trust stores in that directory. 
```
docker exec dse $DSE_JAVA/bin/keytool -genkey -keyalg RSA -alias dse -keystore keystore.dse -storepass cassandra -keypass cassandra -dname "CN=$DSE_IP, OU=None, O=None, L=None, C=None";
```
```
docker exec dse2 $DSE_JAVA/bin/keytool -genkey -keyalg RSA -alias dse2 -keystore keystore.dse2 -storepass cassandra -keypass cassandra -dname "CN=$DSE_IP2, OU=None, O=None, L=None, C=None"
```

4. Export the certificate to be copied to other nodes from each node 
```
docker exec dse $DSE_JAVA/bin/keytool -export -alias dse -file dse.cer -keystore keystore.dse;
```
```
docker exec dse2 $DSE_JAVA/bin/keytool -export -alias dse2 -file dse2.cer -keystore keystore.dse2
```

5. Load the certificate into the trust store on each node
```
docker exec dse $DSE_JAVA/bin/keytool -import -v -trustcacerts -alias dse -file dse.cer -keystore truststore.dse -storepass cassandra -noprompt;
```
```
docker exec dse2 $DSE_JAVA/bin/keytool -import -v -trustcacerts -alias dse2 -file dse2.cer -keystore truststore.dse2 -storepass cassandra -noprompt
```

6. Get certificates in PKS format for cqlsh
`docker exec dse $DSE_JAVA/bin/keytool -importkeystore -srckeystore keystore.dse -destkeystore dse.p12 -deststoretype PKCS12 -srcstorepass cassandra -deststorepass cassandra;`
`docker exec dse2 $DSE_JAVA/bin/keytool -importkeystore -srckeystore keystore.dse2 -destkeystore dse2.p12 -deststoretype PKCS12 -srcstorepass cassandra -deststorepass cassandra`

7. Create a '.pem' file for cqlsh
```
docker exec dse openssl pkcs12 -in dse.p12 -nokeys -out dse.cer.pem -passin pass:cassandra;
```
```
docker exec dse openssl pkcs12 -in dse.p12 -nodes -nocerts -out dse.key.pem -passin pass:cassandra;
```
```
docker exec dse2 openssl pkcs12 -in dse2.p12 -nokeys -out dse2.cer.pem -passin pass:cassandra;
```
```
docker exec dse2 openssl pkcs12 -in dse2.p12 -nodes -nocerts -out dse2.key.pem -passin pass:cassandra
```

8. copy '.cer' files to local docker host
```docker cp dse:/opt/dse/dse.cer .;
``` 
```
docker cp dse2:/opt/dse/dse2.cer .
```

9. copy '.cer' file to other host (so dse.cer to dse2 and dse2.cer to dse)
```
docker cp dse.cer dse2:/opt/dse;
```
```
docker cp dse2.cer dse:/opt/dse
```

10. load the '.cer' file to truststore
```
docker exec dse $DSE_JAVA/bin/keytool -import -v -trustcacerts -alias dse2 -file dse2.cer -keystore truststore.dse -storepass cassandra -noprompt;
```
```
docker exec dse2 $DSE_JAVA/bin/keytool -import -v -trustcacerts -alias dse -file dse.cer -keystore truststore.dse2 -storepass cassandra -noprompt
```

11. Copy all the key related files to a docker volume for container restart
```
docker exec dse bash -c "cp *dse* /etc/dse/conf";
```
```
docker exec dse2 bash -c "cp *dse* /etc/dse/conf"
```

## Configure DSE to use encryption

1. Generate DSE system key on each node
```
docker exec dse dsetool createsystemkey AES/ECB/PKCS5Padding 256 system_key;
```
```
docker exec dse2 dsetool createsystemkey AES/ECB/PKCS5Padding 256 system_key
```
2. Encrypt keystore and truststore password using dsetool.  First getting bash shell and then typing dsetool command.  Save each of these values for subsequent steps.
```
docker exec -i -t dse bash
```
```
dsetool encryptconfigvalue
```
```
docker exec -i -t dse2 bash
```
```
dsetool encryptconfigvalue
```
3. Get a local copy of the dse.yaml file from the dse container.  `docker cp dse:/opt/dse/resources/dse/conf/dse.yaml dse.yaml.clean`  or if you prefer use the existing dse.yaml provided in the github.  However, this existing dse.yaml is for 5.1.6 and may not work in subsequent versions.  Also provided in the github is a diff file call dse.yaml.diff
4. Edit local copy of the dse.yaml being extremely careful to maintain the correct spaces as the yaml is space aware.   Thankfully, any errors are obvious in /var/log/cassandra/system.log on startup failure 
```
(~line 480):
config_encryption_active: true
```
```
(~line 782):
system_info_encryption:
    enabled: true
    cipher_algorithm: AES
    secret_key_strength: 256
    key_name: system_key
```     
5. Save this edited dse.yaml file to the conf subdirectory and to the conf2 directory.  It will be picked up on the next dse restart.  Simplest is just do `cp dse.yaml conf` For notes on this look here:  [https://github.com/datastax/docker-images/#using-the-dse-conf-volume]()
6. Make copy of the cassandra node for each node (don't mix these up).  
```
docker cp dse:/opt/dse/resources/cassandra/conf/cassandra.yaml conf;
```
```
docker cp dse2:/opt/dse/resources/cassandra/conf/cassandra.yaml conf2
```
7. Edit each cassandra.yaml file
 (~line 1055)  the password comes from step 2 (use correct encrypted password for each node)
```
 server_encryption_options:
    internode_encryption: all
    keystore: /etc/dse/conf/keystore.dse
    keystore_password: ZyOPkOf0RgNDgTZkVK50DQ==
    truststore: /etc/dse/conf/truststore.dse
    truststore_password: ZyOPkOf0RgNDgTZkVK50DQ== 
``` 
(~line 1070)  the password comes from step 2 (use correct encrypted password for each node)
```  
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

9. Configure cqlsh to work with encryption.  Use the cqlshrc files from the github for each node. 
`docker cp cqlshrc dse:/opt/dse/.cassandra;`
`docker cp cqlshrc2 dse2:/opt/dse/.cassandra/cqlshrc`
this is the file for doc purposes:

   ```
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

```
docker exec -it dse bash
```

```
cqlsh --ssl
```

```
docker exec -it dse2 bash
```

```
cqlsh --ssl
```

## Enable Transparent Data Encryption on a table.

1. Generate new encryption key
    `docker exec dse dsetool createsystemkey AES/ECB/PKCS5Padding 256 test_table_key;`
    
2. copy encryption key to other node
     `docker cp dse:/etc/dse/conf/test_table_key .;`
     `docker cp test_table_key dse2:/etc/dse/conf`
 
3. Alter table to turn on encryption
```
docker exec dse cqlsh --ssl -e "alter table demo.solr  WITH
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

    ```
    docker exec dse cqlsh --ssl -e "desc demo.solr"    
    ```
5. upgrade the sstables to encrypt on each node.
 ```
 docker exec -it dse bash -c "nodetool upgradesstables -a";
 ```
 ```
 docker exec -it dse2 bash -c "nodetool upgradesstables -a"
 ```

## Enable SOLR encryption
1. turn encryption on the DSE Search 
``` 
docker exec -it dse cqlsh --ssl -e "alter search index config on demo.solr set directoryFactory = 'encrypted'";
```
``` 
docker exec -it dse cqlsh --ssl  -e "reload search index on demo.solr"
```
2.  restart for directoryFactory change
`docker-compose restart`
3.  rebuild the index
``` 
docker exec -it dse cqlsh --ssl  -e "rebuild search index on demo.solr with options {deleteAll :true}"
```
4.  Copy relevant files off the image and use the `strings` command to ensure encryption
5. To generate more records with encryption turned on:
`docker exec dse /opt/dse/demos/solr_stress/run-benchmark.sh --test-data=./resources/testCqlWrite.txt --loops 110000 --cqlSSL --cqlKeystore=/etc/dse/conf/keystore.dse --cqlKeystorePassword=cassandra --cqlTruststore=/etc/dse/conf/truststore.dse --cqlTruststorePassword=cassandra`

## Conclusion
At this point, DSE is set up with encryption


