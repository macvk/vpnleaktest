# VPN Leak Test

These command-line clients run the network checks used by the
[bash.ws VPN test](https://bash.ws/vpn-leak-test). They detect public IPv4 and
IPv6 addresses, check for DNS leaks, scan common ports, check IP blacklists,
and report the server-side connection analysis.

## Linux and macOS

### How to install and use the shell version

Please, before use make sure you have `curl` and `ping` installed.

1. Download `vpnleaktest.sh`:

```sh
curl -fLO https://raw.githubusercontent.com/macvk/vpnleaktest/main/vpnleaktest.sh
```

```sh
chmod +x vpnleaktest.sh
```

2. Run it:

```sh
./vpnleaktest.sh
```

### How to install and use the Python version

Python 3.6 or newer is required.

1. Download `vpnleaktest.py`:

```sh
curl -fLO https://raw.githubusercontent.com/macvk/vpnleaktest/main/vpnleaktest.py
```

```sh
chmod +x vpnleaktest.py
```

2. Run it:

```sh
./vpnleaktest.py
```

-----------------------------------------------------

## Windows

### How to install and use the batch file

Windows PowerShell, `curl.exe`, and `ping.exe` are required.

1. Download `vpnleaktest.bat`:

```powershell
Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/macvk/vpnleaktest/main/vpnleaktest.bat -OutFile vpnleaktest.bat
```

2. Run `vpnleaktest.bat`:

```bat
vpnleaktest.bat
```

-----------------------------------------------------

## Go

### Build from source

Install Go, download `vpnleaktest.go`, and build it for the current platform:

```sh
curl -fLO https://raw.githubusercontent.com/macvk/vpnleaktest/main/vpnleaktest.go
go build -o vpnleaktest vpnleaktest.go
./vpnleaktest
```

Examples for other operating systems and architectures:

```sh
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o vpnleaktest-linux-amd64 vpnleaktest.go
GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 go build -o vpnleaktest-darwin-arm64 vpnleaktest.go
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -o vpnleaktest-windows-amd64.exe vpnleaktest.go
```

## How to run from Docker

### Linux

Use host networking so the test sees the host's network stack and DNS
configuration. This is important when the host uses a local DNS resolver such as
systemd-resolved or NextDNS.

```sh
docker run --rm --network host python:alpine sh -c 'apk add --no-cache iputils >/dev/null && wget -q -O- https://raw.githubusercontent.com/macvk/vpnleaktest/main/vpnleaktest.py | python'
```

### macOS and Windows

Docker Desktop runs containers in a virtual machine, so host networking does not
provide the same view of the host's network configuration as it does on Linux.
The following command tests the connection visible inside the container:

```sh
docker run --rm python:alpine sh -c 'apk add --no-cache iputils >/dev/null && wget -q -O- https://raw.githubusercontent.com/macvk/vpnleaktest/main/vpnleaktest.py | python'
```

## Checks

- Public IPv4 and IPv6 detection
- IPv4/IPv6 provider and country comparison
- DNS leak test
- Common open-port test
- IPv4 and IPv6 blacklist tests
- Proxy-header and Tor exit-node indicators

The clients do not claim that a connection is fully anonymous. A `clean` result
means only that the completed command-line checks did not find a suspicious
network indicator.

## License

MIT
