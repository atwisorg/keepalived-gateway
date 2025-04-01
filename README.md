# KeepAlived-GateWay

Maintaining an available gateway and default route.

## Creating a configuration file

Gateway IP addresses separated by a space:

```shell
GATEWAY="IP [IP]..."
```

IP address of the remote host located behind the gateways for checking ping:

```shell
REMOTE_HOST="IP"
```

If there are more than one gateway and the file is available for downloading via http from a remote host, then use the following options to switch to the gateway with the highest bandwidth.

Path to an existing file on the remote host for speedtest.
In a downloaded file, the size of each line should be 1 byte.
example: `SPEEDTEST_PATH="download/100M"` or `SPEEDTEST_PATH="speedtest/10M"`.

```shell
SPEEDTEST_PATH="path to the file on the remote host"
```

Speedtest execution interval.
Available units: [s]econds, [m]inutes, [h]ours, [d]ays, [w]eeks, [M]onths or [y]ears.
example for running speedtest once per hour: `SPEEDTEST_INTERVAL="1h"`.

```shell
SPEEDTEST_INTERVAL="3600"
```

## Creating a download file at a remote host

To correctly calculate the bandwidth between the gateway and the remote host, you need to generate a special file and make it available for download from the remote host.
To create a 10 megabyte file, run the following command on the remote host:

```shell
printf '%5242880s' '' | sed 's/ /1\n/g' > 10M
```
> the execution time depends on the performance of the remote host;

Then, create files of the required size, for example, 100 megabytes:

```shell
for i in $(seq 1 10)
do
    cat 10M
done > 100M
```

Or 1000 megabytes:
```shell
for i in $(seq 1 100)
do
    cat 10M
done > 1000M
```

Place the generated files in any place convenient for you in the web server directory, available for download via the link.

## Запуск

### Running from the command line

```shell
./keepalived-gateway.sh keepalived-gateway.conf
```

### Running as a systemd service

1. save the script and configuration file to the system directors:

   ```shell
   cp keepalived-gateway.sh   /usr/sbin/
   cp keepalived-gateway.conf /etc/
   ```

2. create a service:

   ```shell
   cat <<SERVICE > /etc/systemd/system/keepalived-gateway.service
   [Unit]
   Description=Keepalived Gateway
   After=network-online.target
   Wants=network-online.target

   [Service]
   ExecStart=/usr/sbin/keepalived-gateway.sh

   [Install]
   WantedBy=multi-user.target
   SERVICE
   ```

3. add the service to autorun:

   ```shell
   systemctl daemon-reload
   systemctl enable keepalived-gateway
   ```

4. start the service:

   ```shell
   systemctl start keepalived-gateway
   ```

5. check the execution status:

   ```shell
   systemctl status keepalived-gateway
   ```

> to stop the service:
> ```shell
> systemctl stop keepalived-gateway
> ```
>
> to disable autorun:
> ```shell
> systemctl disable keepalived-gateway
> ```

### Show current routes

```shell
ip r
```
