export DSE_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' dse)
export LDAP_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' openldap)
echo "DSE_IP is "
echo $DSE_IP
echo "LDAP_IP is "
echo $LDAP_IP
docker exec openldap_main_node_1 bash -c "echo $DSE_IP dse.example.org >> /etc/hosts"
# docker exec openldap bash -c "echo $LDAP_IP ldap.example.org >> /etc/hosts"
