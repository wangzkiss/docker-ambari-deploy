# docker-ambari-deploy

doeker化安装步骤

首先要映射出来的端口需要
mysql 3306
amb的 8080
vigor-etl  15100
vigor-admin 8900


1.安装基础服务 周鹏提供
2.安装etl
   1）传送镜像文件  scp vigor-etl-img.tar root@172.18.84.229:~/
   2）加载镜像文件  docker load < /root/vigor-etl-img.tar
   3）传送启动比脚本 scp start_app root@172.18.84.229:~/
   4）执行启动命令   ./start_app.sh s
   出现的问题：
    a，Error:  dial tcp 172.18.84.220:2379: getsockopt: no route to host
    invalid argument "--dns-search" for --dns: --dns-search is not an ip address
    See 'docker run --help'.
    Template parsing error: template: :1:24: executing "" at <.NetworkSettings.Net...>: map has no entry for key "NetworkSettings"
	./start_app.sh:行24: 2: amb-publish-port <port> <des_ip>
3.安装admin
   1）传送镜像文件  scp vigor-tomcat.tar root@172.18.84.229:~/
   2）加载镜像文件  docker load < /root/vigor-tomcat.tar
   3）传送启动比脚本 scp start_app root@172.18.84.229:~/
   4）执行启动命令   ./start_app.sh start-admin

3.安装vigordata-scheduler.war
   1）传送镜像文件  scp vigor-tomcat.tar root@172.18.84.229:~/
   2）加载镜像文件  docker load < /root/vigor-tomcat.tar
   3）传送启动比脚本 scp start_app root@172.18.84.229:~/
   4）执行启动命令   ./start_app.sh start-admin
