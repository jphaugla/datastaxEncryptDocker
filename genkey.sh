docker exec dse keytool -genkey -keyalg RSA -alias dse -keystore keystore.dse -storepass cassandra -keypass cassandra -dname "CN=$DSE_ID, OU=None, O=None, L=None, C=None"
