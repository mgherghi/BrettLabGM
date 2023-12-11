#!/bin/bash

configuration="config: {}
networks:
- config:
    ipv4.address: 10.154.149.1/24
    ipv4.nat: "true"
    ipv6.address: fd42:f54a:d008:5776::1/64
    ipv6.nat: "true"
  description: ""
  name: lxdbr0
  type: bridge
  project: default
- config:
    ipv4.address: none
    ipv6.address: none
  description: ""
  name: rt
  type: bridge
  project: default
- config:
    ipv4.address: none
    ipv6.address: none
  description: ""
  name: tc
  type: bridge
  project: default
storage_pools:
- config:
    source: /var/snap/lxd/common/lxd/storage-pools/default
  description: ""
  name: default
  driver: dir
profiles:
- config:
    environment.DISPLAY: :0
    cloud-init.user-data: |
      #cloud-config
  description: GUI LXD profile
  devices:
    X0:
      bind: container
      connect: unix:@/tmp/.X11-unix/X10
      listen: unix:@/tmp/.X11-unix/X0
      security.gid: "1000"
      security.uid: "1000"
      type: proxy
  name: gui
- config: {}
  description: Default LXD profile
  devices:
    eth0:
      name: eth0
      network: lxdbr0
      type: nic
    root:
      path: /
      pool: default
      type: disk
  name: default
- config: 
    security.privileged: true
    cloud-init.network-config: |
      network:
        version: 2
        ethernets:
            enp0s3:
                dhcp4: true
            enp0s8:
                dhcp4: false
                addresses:
                    - 192.168.22.101/24
  description: Router LXD profile
  devices:
    enp0s3:
      name: enp0s3
      network: lxdbr0
      type: nic
    enp0s8:
      name: enp0s8
      network: rt
      type: nic
    root:
      path: /
      pool: default
      type: disk
  name: router
- config: 
    security.privileged: true
    cloud-init.network-config: |
      network:
        version: 2
        ethernets:
            enp0s8:
                dhcp4: false
                addresses:
                    - 192.168.22.102/24
                routes:
                    - to: default
                      via: 192.168.22.101
                nameservers:
                    addresses: [8.8.8.8,8.8.4.4]
            enp0s9:
                dhcp4: false
                addresses:
                    - 192.168.23.102/24 
  description: Testing LXD profile
  devices:
    enp0s8:
      name: enp0s8
      network: rt
      type: nic
    enp0s9:
      name: enp0s9
      network: tc
      type: nic
    root:
      path: /
      pool: default
      type: disk
  name: testing
- config: 
    security.privileged: true
    cloud-init.network-config: |
      network:
          version: 2
          ethernets:
              eth0:
                  addresses:
                      - 10.154.149.69/24
              enp0s8:
                  dhcp4: false
                  addresses:
                      - 192.168.23.104/24
                  routes:
                      - to: default
                        via: 192.168.23.102
                  nameservers:
                      addresses: [8.8.8.8,8.8.4.4]
  description: Client LXD profile
  devices:
    eth0:
      name: eth0
      network: lxdbr0
      type: nic
    enp0s8:
      name: enp0s8
      network: tc
      type: nic
    root:
      path: /
      pool: default
      type: disk
  name: client
- config: 
    security.privileged: true
    cloud-init.network-config: |
      network:
          version: 2
          ethernets:
              eth1:
                  dhcp4: false
                  addresses:
                      - 192.168.23.103/24
                  routes:
                      - to: default
                        via: 192.168.23.102
                  nameservers:
                      addresses: [8.8.8.8,8.8.4.4]
  description: Metasploitable LXD profile
  devices:
    eth1:
      name: eth1
      network: tc
      type: nic
    root:
      path: /
      pool: default
      type: disk
  name: metasploitable
projects:
- config:
    features.images: "true"
    features.networks: "true"
    features.networks.zones: "true"
    features.profiles: "true"
    features.storage.buckets: "true"
    features.storage.volumes: "true"
  description: Default LXD project
  name: default"

echo "$configuration" | lxd init --preseed

# just in case this gets changed somehow
lxc remote set-default local
# adds ubuntu-minimal to the remote list, in case it isn't there (ie after lxd is reset or something)
lxc remote add --protocol simplestreams ubuntu-minimal https://cloud-images.ubuntu.com/minimal/releases/

# initialize the profiles to default for internet connection
lxc init ubuntu-minimal:22.04 router --profile router
lxc init ubuntu-minimal:22.04 testing --profile default
lxc init ubuntu-minimal:22.04 metasploitable --profile default
lxc start router
lxc start testing
lxc start metasploitable

# install ping, which is needed for lab 1
lxc exec router -- apt update
lxc exec testing -- apt update
lxc exec metasploitable -- apt update

lxc exec router -- apt install -y iputils-ping
lxc exec testing -- apt install -y iputils-ping
lxc exec metasploitable -- apt install -y iputils-ping

lxc stop testing
lxc stop metasploitable

# correct profiles
lxc profile add testing testing
lxc profile add metasploitable metasploitable

lxc profile remove testing default
lxc profile remove metasploitable default

lxc start testing
lxc start metasploitable

# client setup is special, since it requires GUI access
lxc launch ubuntu-minimal:22.04 -p default -p gui client

lxc exec client -- apt update

# these commands are run to allow access to the browser in the client container while using the host container's GUI
lxc exec client -- sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
lxc exec client -- sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords yes/g' /etc/ssh/sshd_config
lxc exec client -- sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config

# install necessities for x11 / display functionality in client container
lxc exec client -- apt install -y x11-apps
lxc exec client -- apt install -y mesa-utils
lxc exec client -- apt install -y gedit
lxc exec client -- apt install -y xauth

# restart the container
lxc exec client -- reboot

# wait for restart
sleep 5

# install the .deb version of firefox
lxc exec client -- apt install -y software-properties-common
lxc exec client -- add-apt-repository --yes ppa:mozillateam/ppa
lxc exec client -- bash -c  "echo '
Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001

Package: firefox
Pin: version 1:1snap1-0ubuntu2
Pin-Priority: -1
' | tee /etc/apt/preferences.d/mozilla-firefox"

lxc exec client -- apt install -y firefox
lxc exec client -- apt install iputils-ping

lxc exec client -- bash -c 'echo -e "cyber\ncyber" | passwd'

lxc stop client

# add client to the lab configuration - it uses default at first for internet connection
lxc profile add client client
lxc profile remove client default

lxc start client

