# Pre-requisites
```
gem install activesupport
gem install msgpack
```

# Install
```
wget https://raw.githubusercontent.com/tomlobato/munin-passenger/master/munin-passenger.rb -O /usr/local/sbin/munin-passenger.rb
chmod 755 /usr/local/sbin/munin-passenger.rb
munin-passenger.rb install
/etc/init.d/munin-node restart
```
