# Install

1)
```
wget https://raw.githubusercontent.com/tomlobato/munin-passenger5/master/passenger
chmod 755 passenger
mv passenger /etc/munin/plugins/passenger
```

2)
Add this to /etc/munin/plugin-conf.d/munin-node :
```
[passenger]
user root
env.PASSENGER_INSTANCE_REGISTRY_DIR /tmp/aptmp
```

3)
```
/etc/init.d/munin-node restart
```
