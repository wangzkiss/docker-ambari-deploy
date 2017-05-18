# Trouble shooting
## Error info: hbase data remain
```
java.io.IOException: Timedout 300000ms waiting for namespace table to be assigned
```
- delete dir on hadoop

```
hadoop fs -rm -r -f /apps/hbase/
```
- stop Hbase service from ambari
- remove Hbase service
- add Hbase service
