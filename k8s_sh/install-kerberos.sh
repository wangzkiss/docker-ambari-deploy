yum install krb5-server krb5-libs krb5-workstation


vi /etc/krb5.conf
default_realm = EXAMPLE.COM
[realms]
 EXAMPLE.COM = {
  kdc = amb-0.agent.ambari.svc.k8s
  admin_server = amb-0.agent.ambari.svc.k8s
 }

[Use the utility kdb5_util to create the Kerberos database.]
kdb5_util create -s -r EXAMPLE.COM

[Start the KDC]
systemctl start krb5kdc
systemctl start kadmin


[Create a Kerberos Admin]
[Create a KDC admin by creating an admin principal.]
kadmin.local -q "addprinc admin/admin"


[Confirm that this admin principal has permissions in the KDC ACL. Using a text editor,open the KDC ACL file]:
vi /var/kerberos/krb5kdc/kadm5.acl
*/admin@EXAMPLE.COM     *


[After editing and saving the kadm5.acl file, you must restart the kadmin process.]
systemctl restart kadmin

[copy krb5.conf to ambari-server host]
scp /etc/krb5.conf ambari-server.ambari:/etc/

kinit admin/admin
# kinit -k -t /etc/security/keytabs/zk.service.keytab zookeeper/amb-0.agent.ambari.svc.k8s@EXAMPLE.COM
klist




[Enabling Kerberos Security]

[Install the JCE]
openjdk aleady install JCE

[ambari configure Kerberos]
KDC hosts: amb-0.agent.ambari.svc.k8s
Realm name: EXAMPLE.COM
Domains: .agent.ambari.svc.k8s,agent.ambari.svc.k8s,.ambari.svc.k8s,ambari.svc.k8s


Kadmin host: amb-0.agent.ambari.svc.k8s
Admin principal: admin/admin@EXAMPLE.COM
Admin password: 123456


[trouble shooting on ambari-server ]
cat /var/lib/ambari-server/resources/common-services/ZOOKEEPER/3.4.5/package/templates/zookeeper_client_jaas.conf.j2

Client {
com.sun.security.auth.module.Krb5LoginModule required
useKeyTab=true
storeKey=true
useTicketCache=false
keyTab="{{zk_keytab_path}}"
principal="{{zk_principal}}";
};

systemctl restart ambari-server




[connect Hive]
[trouble shooting +++
error:Failed to open new session: java.lang.RuntimeException: java.lang.RuntimeException: org.apache.hadoop.ipc.RemoteException(org.apache.hadoop.security.authorize.AuthorizationException): Unauthorized connection for super-user

In Ambari Web, browse to Services > HDFS > Configs.
Under the Advanced tab, navigate to the Custom core-site section.
change hadoop.proxyuser.hive.hosts=*, hadoop.proxyuser.hcat.hosts=*
]

su hdfs
kinit -k -t /etc/security/keytabs/hdfs.headless.keytab hdfs-test
beeline -u "jdbc:hive2://amb-2.agent.ambari.svc.k8s:10000/;principal=hive/amb-2.agent.ambari.svc.k8s@EXAMPLE.COM" 

su hbase
kinit -k -t /etc/security/keytabs/hbase.headless.keytab hbase-test
hbase shell

[ Set Up Kerberos for Ambari Server (not configuration right now)
1. Create a principal in your KDC for the Ambari Server. For example, using kadmin:
    addprinc -randkey ambari-server@EXAMPLE.COM
2. Generate a keytab for that principal.
    xst -k ambari.server.keytab ambari-server@EXAMPLE.COM
3. Place that keytab on the Ambari Server host. Be sure to set the file permissions so the
    user running the Ambari Server daemon can access the keytab file.
    /etc/security/keytabs/ambari.server.keytab
4. Stop the ambari server.
    ambari-server stop
5. Run the setup-security command.
    ambari-server setup-security
6. Select 3 for Setup Ambari kerberos JAAS configuration.
7. Enter the Kerberos principal name for the Ambari Server you set up earlier.
8. Enter the path to the keytab for the Ambari principal.
9. Restart Ambari Server.
    ambari-server restart
]
