[Ambari install Knox]

[config knox proxyuser]
In Ambari Web, browse to Services > HDFS > Configs.
Under the Advanced tab, navigate to the Custom core-site section.
change hadoop.proxyuser.knox.hosts=*, hadoop.proxyuser.knox.groups=*

[start Demo LDAP]
Start the Knox "Demo LDAP" from Ambari under Knox -> Service actions as shown below 

[test]
curl -sk -L "http://amb-0.agent.ambari.svc.k8s:50070/webhdfs/v1/user/?op=LISTSTATUS"

curl -iv -k -u guest:guest-password https://amb-0.agent.ambari.svc.k8s:8443/gateway/default/webhdfs/v1/?op=LISTSTATUS
curl -iv -k -u admin:admin-password https://amb-0.agent.ambari.svc.k8s:8443/gateway/default/webhdfs/v1/?op=LISTSTATUS
curl -iv -k -u admin:admin-password https://amb-0.agent.ambari.svc.k8s:8443/gateway/default/sparkhistory
curl -iv -k -u guest:guest-password https://172.18.84.221:30443/gateway/default/webhdfs/v1/?op=LISTSTATUS

[web]
https://172.18.84.221:30443/gateway/default/webhdfs/v1/?op=LISTSTATUS
https://172.18.84.221:30443/gateway/default/templeton/v1/version






[Install Ranger]

db host=amb-mysql
audit log store: disable solor, enable db


[trouble shooting
updated_at had unsupported default value
vi /usr/hdp/current/ranger-admin/db/mysql/create_dbversion_catalog.sql
(updated_at      timestamp not null default current_timestamp,)
]

