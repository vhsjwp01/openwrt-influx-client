A bash based influxdb client for OpenWRT

## Working:
- memory metrics
- cpu 1,5,15 minute load metrics
- cpu usage metrics
- process metrics
- netstat metrics
- nstat metrics
- network adapter metrics
- disk usage metrics

## TODO:
- diskio metrics

## BEFORE YOU INSTALL:
- Needed runtime commands:
```opkg install bash bc coreutils coreutils-stat curl sysstat```
- Helpful additional commands:
```opkg install coreutils-cksum diffutils htop jq vim```
