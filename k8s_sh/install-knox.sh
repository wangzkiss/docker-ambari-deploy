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


[Install Ranger KMS]
1.Mysql db host: amb-mysql

2.Add values for the following properties in the "Custom kms-site" section

hadoop.kms.proxyuser.hive.users
hadoop.kms.proxyuser.oozie.users
hadoop.kms.proxyuser.HTTP.users
hadoop.kms.proxyuser.ambari.users
hadoop.kms.proxyuser.yarn.users
hadoop.kms.proxyuser.hive.hosts
hadoop.kms.proxyuser.oozie.hosts
hadoop.kms.proxyuser.HTTP.hosts
hadoop.kms.proxyuser.ambari.hosts
hadoop.kms.proxyuser.yarn.hosts

3.Add the following properties to the Custom KMS-site section of the configuration
hadoop.kms.proxyuser.keyadmin.groups=*
hadoop.kms.proxyuser.keyadmin.hosts=*
hadoop.kms.proxyuser.keyadmin.users=*


[Enable HDFS encryption]
1. At Ranger KMS Host link config file
sudo ln -s /etc/hadoop/conf/core-site.xml /etc/ranger/kms/conf/
core-site.xml

2.Configure HDFS to access Ranger KMS.
Advanced core-site
    hadoop.security.key.provider.path = kms://http@amb-0.agent.ambari.svc.k8s:9292/kms
Advanced hdfs-site
    dfs.encryption.key.provider.uri = kms://http@amb-0.agent.ambari.svc.k8s:9292/kms

3. Under Custom core-site.xml, set the value of the hadoop.proxyuser.kms.groups
property to * or service user.

4. Restart the Ranger KMS service and the HDFS service.