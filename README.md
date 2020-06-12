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
```opkg install coreutils coreutils-stat curl bash bc```
- Helpful additional commands:
```opkg install coreutils-cksum diffutils htop vim```
