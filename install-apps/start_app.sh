#!/bin/bash

# import common variable
: ${DIR_HOME:=$(dirname $0)}
source ${DIR_HOME}/env.sh
#base info
: ${MYSQL_HOST:=mysql.service.consul}
: ${KYLIN_HOST:=kylin.service.consul}
: ${AMR_URL_PORT:=8080}
: ${AMR_URL_HOST:=amb-server.service.consul}
# def  etl
: ${ETL_NAME:=vigor-etl}
: ${ETL_PORT:=15100}
# def  admin
: ${ADMIN_NAME:=vigor-admin}
: ${ADMIN_PORT:=8900}
: ${ADMIN_WAR:=vigordata-web}
: ${AMR_DATA_HOST_PWD:=Zasd_1234}
: ${AMR_DATA_HOST:=amb1.service.consul}

# def  sch
: ${SCHEDULER_NAME:=vigor-scheduler}
: ${SCHEDULER_PORT:=8901}
: ${SCHEDULER_WAR:=vigordata-scheduler}

# def  batch
: ${BATCH_NAME:=vigor-batch}
: ${BATCH_PORT:=8902}
: ${BATCH_WAR:=vigordata-batchagent}
: ${HSFS_SERVER_NAME:=xdata2}

# def  etlagent
: ${ETLAGENT_NAME:=vigor-etlagent}
: ${ETLAGENT_PORT:=8903}
: ${ETLAGENT_WAR:=vigordata-etlagent}

# def  vigordata-streamingagent 
: ${STREAMING_NAME:=vigor-streaming}
: ${STREAMING_PORT:=8904}
: ${STREAMING_WAR:=vigordata-streamingagent}


load_image(){
	## docker load < ./vigor-etl-img.tar
	## docker load < ./vigor-tomcat.tar
	local filename=${1:?"load_image <filename>]"}
	docker load < ${DIR_HOME}/${filename}
}

#start etl server
start_etl(){
    
    local consul_ip=$(get-consul-ip)
    docker stop ${ETL_NAME} && docker rm ${ETL_NAME}
    docker run  --net ${CALICO_NET} --dns $consul_ip  --dns-search service.consul --name ${ETL_NAME} -p ${ETL_PORT}:${ETL_PORT}  -d vigor-etl $MYSQL_HOST ${ETL_PORT} 
    
    ## 加载配置文件 
    ## /home/vigor-etl/plugins/pentaho-big-data-plugin/hadoop-configurations/hdp21
    ## /usr/hdp/2.4.0.0-169/hadoop/etc/hadoop    
	docker exec ${ETL_NAME}  sh -c "echo -e  'y\n'|ssh-keygen -q -t rsa -N '' -f ~/.ssh/id_rsa"
	docker exec ${ETL_NAME}  sh -c "ssh-keyscan ${AMR_DATA_HOST} >> ~/.ssh/known_hosts" 
	docker exec ${ETL_NAME}  sh -c "sshpass -p ${AMR_DATA_HOST_PWD} scp -r root@${AMR_DATA_HOST}:/usr/hdp/2.4.0.0-169/hadoop/etc/hadoop/*.xml    /home/${ETL_NAME}/plugins/pentaho-big-data-plugin/hadoop-configurations/hdp21/"
	docker exec ${ETL_NAME}  sh -c "sshpass -p ${AMR_DATA_HOST_PWD} scp -r root@${AMR_DATA_HOST}:/usr/hdp/2.4.0.0-169/hbase/conf/*.xml    /home/${ETL_NAME}/plugins/pentaho-big-data-plugin/hadoop-configurations/hdp21/"

	#get ip of  this container 
	docker stop ${ETL_NAME} && docker start ${ETL_NAME}
	
	##开放端口
	local app_ip=$(docker inspect --format="{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" ${ETL_NAME})
	amb-publish-port $app_ip ${ETL_PORT} 
	
	##注册dns
	consul-register-service ${ETL_NAME} $app_ip
	

}


# 要求home目录大小不少于500M
start_admin(){
	#创建目录 赋予权限
	mkdir -p /home/${ADMIN_NAME}/webapps
	chmod -R 777 /home/${ADMIN_NAME}/webapps

	docker stop ${ADMIN_NAME} && docker rm  ${ADMIN_NAME}
	## 
	/bin/cp -rf "${DIR_HOME}/${ADMIN_WAR}.war" /home/${ADMIN_NAME}/webapps
	cd /home/${ADMIN_NAME}/webapps/
	rm -rf ${ADMIN_WAR}
	unzip -q "${ADMIN_WAR}.war" -d ${ADMIN_WAR}
	if [ $? ]; then
		# ##修改配置文件
		sed -i "/jdbc.url/{s/\/.*:/\/\/${MYSQL_HOST}:/g}"   /home/${ADMIN_NAME}/webapps/${ADMIN_WAR}/WEB-INF/classes/tospur.properties
		sed -i "/kylin_base_api_url/{s/\/.*:/\/\/${KYLIN_HOST}:/g}"   /home/${ADMIN_NAME}/webapps/${ADMIN_WAR}/WEB-INF/classes/tospur.properties
		sed -i "/ambr_host/{s/=.*/= ${AMR_URL_HOST}/g}"   /home/${ADMIN_NAME}/webapps/${ADMIN_WAR}/WEB-INF/classes/tospur.properties
		sed -i "/ambr_port/{s/=.*/= ${AMR_URL_PORT}/g}"   /home/${ADMIN_NAME}/webapps/${ADMIN_WAR}/WEB-INF/classes/tospur.properties
		sed -i "/hdfs_nameservices/{s/=.*/= ${HSFS_SERVER_NAME}/g}"   /home/${ADMIN_NAME}/webapps/${ADMIN_WAR}/WEB-INF/classes/tospur.properties
		sed -i "/kylin_default_project/{s/=.*/= ${ADMIN_WAR}/g}"   /home/${ADMIN_NAME}/webapps/${ADMIN_WAR}/WEB-INF/classes/tospur.properties


		local consul_ip=$(get-consul-ip)
		docker run  --privileged  --net ${CALICO_NET} --dns $consul_ip  --name ${ADMIN_NAME}  -v /home/${ADMIN_NAME}/webapps:/usr/local/tomcat/webapps  -d  vigor-tomcat 
		docker exec ${ADMIN_NAME}  sh -c "echo -e  'y\n'|ssh-keygen -q -t rsa -N '' -f ~/.ssh/id_rsa"
		docker exec ${ADMIN_NAME}  sh -c "ssh-keyscan ${AMR_DATA_HOST} >> ~/.ssh/known_hosts" 
		docker exec ${ADMIN_NAME}  sh -c "sshpass -p ${AMR_DATA_HOST_PWD} scp -r root@${AMR_DATA_HOST}:/usr/hdp/2.4.0.0-169/hadoop/etc/hadoop/*.xml    /usr/local/tomcat/webapps/${ADMIN_WAR}/WEB-INF/classes/"
		docker exec ${ADMIN_NAME}  sh -c "sshpass -p ${AMR_DATA_HOST_PWD} scp -r root@${AMR_DATA_HOST}:/usr/hdp/2.4.0.0-169/hbase/conf/*.xml    /usr/local/tomcat/webapps/${ADMIN_WAR}/WEB-INF/classes/"
		##docker exec vigor-etl sh -c  "sshpass -p Zasd_1234  scp -r root@amb1.service.consul:/usr/hdp/2.4.0.0-169/hbase/conf/*.xml    /usr/local/tomcat/webapps/vigordata-web/WEB-INF/classes/"
		docker stop ${ADMIN_NAME} && docker start ${ADMIN_NAME}
		local app_ip=$(docker inspect --format="{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" ${ADMIN_NAME})
		amb-publish-port $app_ip ${ADMIN_PORT} 8080
	else 
		exit -1
	fi

}
# 要求vigordata-scheduler.war  目录大小不少于500M
start_sch(){
	#创建目录 赋予权限
	mkdir -p /home/${SCHEDULER_NAME}/webapps
	chmod -R 777 /home/${SCHEDULER_NAME}/webapps
	docker stop ${SCHEDULER_NAME} && docker rm  ${SCHEDULER_NAME}
	## 
	/bin/cp -rf "${DIR_HOME}/${SCHEDULER_WAR}.war" /home/${SCHEDULER_NAME}/webapps
	cd /home/${SCHEDULER_NAME}/webapps/
	rm -rf ${SCHEDULER_WAR}
	unzip -q "${SCHEDULER_WAR}.war" -d ${SCHEDULER_WAR}
	if [ $? ]; then
		sed -i "/jdbc:mysql/{s/\/.*:/\/\/${MYSQL_HOST}:/g}"   /home/${SCHEDULER_NAME}/webapps/${SCHEDULER_WAR}/WEB-INF/classes/activiti.cfg.xml
		sed -i "/jdbc:mysql/{s/\/.*:/\/\/${MYSQL_HOST}:/g}"   /home/${SCHEDULER_NAME}/webapps/${SCHEDULER_WAR}/WEB-INF/classes/conf.properties
		sed -i "/kylin_api_url/{s/\/.*:/\/\/${KYLIN_HOST}:/g}"   /home/${SCHEDULER_NAME}/webapps/${SCHEDULER_WAR}/WEB-INF/classes/conf.properties
		
		local consul_ip=$(get-consul-ip)
		
		docker run  --privileged  --net ${CALICO_NET} --dns $consul_ip  --name ${SCHEDULER_NAME}  -v /home/${SCHEDULER_NAME}/webapps:/usr/local/tomcat/webapps  -d  vigor-tomcat 
		
		##开放端口
		local app_ip=$(docker inspect --format="{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" ${SCHEDULER_NAME})
		amb-publish-port $app_ip ${SCHEDULER_PORT} 8080
		
		##注册dns
		consul-register-service ${SCHEDULER_NAME} $app_ip
	else
		exit -1
	fi
}
# 启动计算子系统
start_batch(){
	#创建目录 赋予权限
	mkdir -p /home/${BATCH_NAME}/webapps
	chmod -R 777 /home/${BATCH_NAME}/webapps
	## 
	docker stop ${BATCH_NAME} && docker rm  ${BATCH_NAME}
	/bin/cp -rf "${DIR_HOME}/${BATCH_WAR}.war" /home/${BATCH_NAME}/webapps
	cd /home/${BATCH_NAME}/webapps/
	rm -rf ${BATCH_WAR}
	unzip -q "${BATCH_WAR}.war" -d ${BATCH_WAR}
	if [ $? ]; then
		## 修改配置文件  fs.defaultFS=hdfs://xdata2 
		sed -i "/jdbc:mysql/{s/\/.*:/\/\/${MYSQL_HOST}:/g}"   /home/${BATCH_NAME}/webapps/${BATCH_WAR}/WEB-INF/classes/compute-config.properties
		sed -i "/defaultFS/{s/=.*/= hdfs:\/\/${HSFS_SERVER_NAME}/g}"   /home/${BATCH_NAME}/webapps/${BATCH_WAR}/WEB-INF/classes/compute-config.properties
		local consul_ip=$(get-consul-ip)
		docker run  --privileged  --net ${CALICO_NET} --dns $consul_ip  --name ${BATCH_NAME}  -v /home/${BATCH_NAME}/webapps:/usr/local/tomcat/webapps  -d  vigor-tomcat 
		##开放端口
		docker exec ${BATCH_NAME}  sh -c "echo -e  'y\n'|ssh-keygen -q -t rsa -N '' -f ~/.ssh/id_rsa"
		docker exec ${BATCH_NAME}  sh -c "ssh-keyscan ${AMR_DATA_HOST} >> ~/.ssh/known_hosts" 
		docker exec ${BATCH_NAME}  sh -c "sshpass -p ${AMR_DATA_HOST_PWD} scp -r root@${AMR_DATA_HOST}:/usr/hdp/2.4.0.0-169/hadoop/etc/hadoop/*.xml    /usr/local/tomcat/webapps/${BATCH_WAR}/WEB-INF/classes/"
		docker stop ${BATCH_NAME} && docker start  ${BATCH_NAME}
		local app_ip=$(docker inspect --format="{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" ${BATCH_NAME})
		amb-publish-port $app_ip ${BATCH_PORT} 8080

		##注册dns
		consul-register-service ${BATCH_NAME} $app_ip
	else 
		exit -1
	fi
}
# 启动etl子系统
start_etlagent(){
	#创建目录 赋予权限
	mkdir -p /home/${ETLAGENT_NAME}/webapps
	chmod -R 777 /home/${ETLAGENT_NAME}/webapps
	## 
	docker stop ${ETLAGENT_NAME} && docker rm  ${ETLAGENT_NAME}
	
	/bin/cp -rf "${DIR_HOME}/${ETLAGENT_WAR}.war" /home/${ETLAGENT_NAME}/webapps
	cd /home/${ETLAGENT_NAME}/webapps/
	rm -rf ${ETLAGENT_WAR}
	unzip -q "${ETLAGENT_WAR}.war" -d ${ETLAGENT_WAR}
	## 修改配置文件  fs.defaultFS=hdfs://xdata2 
	if [ $? ]; then
		sed -i "/repo_db_host/{s/=.*/= ${MYSQL_HOST}/g}"   /home/${ETLAGENT_NAME}/webapps/${ETLAGENT_WAR}/WEB-INF/classes/config.properties
		sed -i "/etl_server_path/{s/=.*/= \/home\/vigor-etl\//g}"   /home/${ETLAGENT_NAME}/webapps/${ETLAGENT_WAR}/WEB-INF/classes/config.properties
		sed -i "/repository_name/{s/=.*/= ebd/g}"   /home/${ETLAGENT_NAME}/webapps/${ETLAGENT_WAR}/WEB-INF/classes/config.properties

		local consul_ip=$(get-consul-ip)
		
		docker run  --privileged  --net ${CALICO_NET} --dns $consul_ip  --name ${ETLAGENT_NAME}  -v /home/${ETLAGENT_NAME}/webapps:/usr/local/tomcat/webapps  -d  vigor-tomcat 
		##开放端口
		local app_ip=$(docker inspect --format="{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" ${ETLAGENT_NAME})
		
		amb-publish-port $app_ip ${ETLAGENT_PORT} 8080
		##注册dns
		consul-register-service ${ETLAGENT_NAME} $app_ip
	else
		exit -1
	fi
}
#启动flumeagent
start_stream(){
	#创建目录 赋予权限
	mkdir -p /home/${STREAMING_NAME}/webapps
	chmod -R 777 /home/${STREAMING_NAME}/webapps
	## 
	docker stop ${STREAMING_NAME} && docker rm  ${STREAMING_NAME}
	/bin/cp -rf "${DIR_HOME}/${STREAMING_WAR}.war" /home/${STREAMING_NAME}/webapps
	cd /home/${STREAMING_NAME}/webapps/
	rm -rf ${STREAMING_WAR}
	unzip -q "${STREAMING_WAR}.war" -d ${STREAMING_WAR}
	## 修改配置文件  fs.defaultFS=hdfs://xdata2 
 	if [ $? ]; then
		local consul_ip=$(get-consul-ip)
		
		docker run  --privileged  --net ${CALICO_NET} --dns $consul_ip  --name ${STREAMING_NAME}  -v /home/${STREAMING_NAME}/webapps:/usr/local/tomcat/webapps  -d  vigor-tomcat 
		##开放端口
		local app_ip=$(docker inspect --format="{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" ${STREAMING_NAME})
		amb-publish-port $app_ip ${STREAMING_PORT} 8080
		##注册dns
		consul-register-service ${STREAMING_NAME} $app_ip
	else
		exit -1
	fi
}

restart(){
	local container=${1:?"restart <container>"}
	local container_port=8900
	docker stop ${container} && docker start  ${container}
	local app_ip=$(docker inspect --format="{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" ${container})
	case ${container} in 
         ${ADMIN_NAME}) 
          container_port=${ADMIN_PORT}
          ##开放端口
		  amb-publish-port $app_ip ${container_port} 8080
		  consul-register-service ${container} $app_ip
         ;; 
          ${ETL_NAME}) 
          container_port=${ETL_PORT}
          amb-publish-port $app_ip ${container_port}
          consul-register-service ${container} $app_ip
         ;; 
          ${BATCH_NAME}) 
          container_port=${BATCH_PORT}
          amb-publish-port $app_ip ${container_port} 8080
          consul-register-service ${container} $app_ip
         ;; 
          ${SCHEDULER_NAME}) 
          container_port=${SCHEDULER_PORT}
          amb-publish-port $app_ip ${container_port} 8080
          consul-register-service ${container} $app_ip

         ;; 
          ${ETLAGENT_NAME}) 
          container_port=${ETLAGENT_PORT}
          amb-publish-port $app_ip ${container_port} 8080
          consul-register-service ${container} $app_ip
         ;; 
         ${STREAMING_NAME}) 
          container_port=${STREAMING_PORT}
          amb-publish-port $app_ip ${container_port} 8080
          consul-register-service ${container} $app_ip
         ;; 
         *) 
           echo "Ignorant" 
         ;; 
    esac 
    ##注册dns
    echo $container_port $app_ip
}


amb-publish-port() {
  local container_ip=${1:?"amb-publish-port <container_ip> <host_port> [<container_port>]"}
  local host_port=${2:?"amb-publish-port <container_ip> <host_port> [<container_port>]"}
  local container_port=$3

  for i in $( iptables -nvL INPUT --line-numbers | grep $host_port | awk '{ print $1 }' | tac ); \
    do iptables -D INPUT $i; done
  iptables -A INPUT -m state --state NEW -p tcp --dport $host_port -j ACCEPT
  
  for i in $( iptables -t nat --line-numbers -nvL PREROUTING | grep $host_port | awk '{ print $1 }' | tac ); \
    do iptables -t nat -D PREROUTING $i; done
  for i in $( iptables -t nat --line-numbers -nvL OUTPUT | grep $host_port | awk '{ print $1 }' | tac ); \
    do iptables -t nat -D OUTPUT $i; done

  if [ -z $container_port ]; then
    iptables -A PREROUTING -t nat -i eth0 -p tcp --dport $host_port -j DNAT  --to ${container_ip}:$host_port
    iptables -t nat -A OUTPUT -p tcp -o lo --dport $host_port -j DNAT --to-destination ${container_ip}:$host_port
  else
    iptables -A PREROUTING -t nat -i eth0 -p tcp --dport $host_port -j DNAT  --to ${container_ip}:$container_port
    iptables -t nat -A OUTPUT -p tcp -o lo --dport $host_port -j DNAT --to-destination ${container_ip}:$container_port
  fi

  service iptables save
}


# call arguments verbatim:
$@