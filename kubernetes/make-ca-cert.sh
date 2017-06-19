#!/bin/bash

cert_dir=${CERT_DIR:-/srv/kubernetes}

create_ca(){
  openssl genrsa -out $cert_dir/ca.key 2048
  openssl req -x509 -new -nodes -key $cert_dir/ca.key -days 10000 -out $cert_dir/ca.crt -subj "/CN=kube-apiserver"
}

create_server(){
  local master_host=${1:?"create_server <MASTER_HOST>"}

  cat << EOF > $cert_dir/openssl.cnf
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster.local
IP.1 = 10.254.0.1
IP.2 = ${master_host}
EOF

  openssl genrsa -out $cert_dir/server.key 2048
  openssl req -new -key $cert_dir/server.key -out $cert_dir/server.csr -subj "/CN=kube-server" -config $cert_dir/openssl.cnf
  openssl x509 -req -in $cert_dir/server.csr -CA $cert_dir/ca.crt -CAkey $cert_dir/ca.key -CAcreateserial \
           -out $cert_dir/server.cert -days 365 -extensions v3_req -extfile $cert_dir/openssl.cnf

}

create_client(){
  cat << EOF > $cert_dir/worker-openssl.cnf
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
EOF

  openssl genrsa -out $cert_dir/kubecfg.key 2048
  openssl req -new -key $cert_dir/kubecfg.key -subj "/CN=kubecfg" -out $cert_dir/kubecfg.csr -config $cert_dir/worker-openssl.cnf
  openssl x509 -req -in $cert_dir/kubecfg.csr -CA $cert_dir/ca.crt -CAkey $cert_dir/ca.key -CAcreateserial \
           -out $cert_dir/kubecfg.crt -days 5000 -extensions v3_req -extfile $cert_dir/worker-openssl.cnf
}

main(){
  local master_host=${1:?"main <MASTER_HOST>"}
  mkdir -p "$cert_dir"

  create_ca
  create_server $master_host
  create_client
}


$@


