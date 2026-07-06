# AI Home Datacenter Inventory

Generated: 2026. 07. 06. (월) 23:53:12 UTC

## Role

- Mac mini M4: Brain / AI Control Plane / Always ON
- Ubuntu Server: Worker / Storage / Docker Services / On-demand

## Server

```
 Static hostname: hanas
       Icon name: computer-desktop
         Chassis: desktop
      Machine ID: bdbeb95396204a48a15094e5742713ac
         Boot ID: d8c39b6fb42c41bb8f9d6740fd21958e
Operating System: Ubuntu 22.04.5 LTS
          Kernel: Linux 5.15.0-185-generic
    Architecture: x86-64
 Hardware Vendor: To Be Filled By O.E.M.
  Hardware Model: A320M-HDV R4.0
```

## IP

```
192.168.1.7 172.18.0.1 172.17.0.1 
```

## Disks

```
NAME     SIZE MODEL            SERIAL         MOUNTPOINT
loop0   55.5M                                 /snap/core18/2952
loop1   55.5M                                 /snap/core18/2999
loop2   63.8M                                 /snap/core20/2599
loop3   63.8M                                 /snap/core20/2669
loop4   91.9M                                 /snap/lxd/32662
loop5   91.9M                                 /snap/lxd/38688
loop7   50.8M                                 /snap/snapd/25202
loop8   50.1M                                 /snap/snapd/27406
sda    232.9G ST3250820AS      5QE49V17       
└─sda1 232.9G                                 /home/han/Backup
sdb      3.6T ST4000DM004-2CV1 WFN5DG02       
└─sdb1   3.6T                                 /mnt/storage
sdc    596.2G SAMSUNG HM641JI  S26XJDQZ603087 
└─sdc1 596.2G                                 
sdd    238.5G SAMSUNG MZNTY256 S2ZSNB0HA45733 
├─sdd1   512M                                 /boot/efi
└─sdd2   238G                                 /
```

## Disk Usage

```
파일 시스템     크기  사용  가용 사용% 마운트위치
/dev/sdd2       234G  108G  114G   49% /
/dev/sdb1       3.6T  2.1T  1.4T   62% /mnt/storage
/dev/sda1       229G   34G  184G   16% /home/han/Backup
```

## Docker Containers

```
NAMES                     STATUS                       PORTS
immich_server             Up About an hour (healthy)   0.0.0.0:2283->2283/tcp, [::]:2283->2283/tcp
nextcloud                 Up 2 hours                   0.0.0.0:8080->80/tcp, [::]:8080->80/tcp
nextcloud_postgres        Up 2 hours (healthy)         5432/tcp
nextcloud_redis           Up 2 hours (healthy)         6379/tcp
immich_postgres           Up 2 hours (healthy)         5432/tcp
immich_machine_learning   Up 2 hours (healthy)         
immich_redis              Up 2 hours (healthy)         6379/tcp
portainer                 Up 8 hours                   8000/tcp, 9000/tcp, 0.0.0.0:9443->9443/tcp, [::]:9443->9443/tcp
homepage                  Up 2 hours (healthy)         0.0.0.0:3000->3000/tcp, [::]:3000->3000/tcp
```

## Compose Services

```
/opt/aihomedatacenter/compose/immich/compose.yml
/opt/aihomedatacenter/compose/portainer/compose.yml
/opt/aihomedatacenter/compose/nextcloud/compose.yml
/opt/aihomedatacenter/compose/homepage/compose.yml
```

## Open Ports

```
tcp   LISTEN 0      4096              0.0.0.0:8080       0.0.0.0:*          
tcp   LISTEN 0      4096              0.0.0.0:3000       0.0.0.0:*          
tcp   LISTEN 0      4096              0.0.0.0:2283       0.0.0.0:*          
tcp   LISTEN 0      4096              0.0.0.0:9443       0.0.0.0:*          
tcp   LISTEN 0      4096                 [::]:8080          [::]:*          
tcp   LISTEN 0      4096                 [::]:3000          [::]:*          
tcp   LISTEN 0      4096                 [::]:2283          [::]:*          
tcp   LISTEN 0      4096                 [::]:9443          [::]:*          
```

## Git

```
Branch: main
?? docs/INVENTORY.md
?? reports/
?? scripts/cleanup.sh
?? scripts/inventory.sh
?? scripts/menu.sh
?? scripts/monitor.sh
?? scripts/plex.sh
?? scripts/report.sh
?? scripts/scheduler.sh
```

## Known Issue

- /dev/sdc Samsung HM641JI: I/O error, FPDMA, DID_BAD_TARGET
- Action: Do not use until SATA cable/port replacement
