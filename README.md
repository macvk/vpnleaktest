# VPN Leak Test

The [VPN leak test](https://bash.ws/vpn-leak-test) combines several tests into
one: it checks public IPv4 and IPv6 addresses, DNS leaks, open ports, IP
blacklists, proxy headers, Tor exit nodes, and location.

## Linux and macOS

### Shell

Download the shell script:

```sh
curl -fLO https://raw.githubusercontent.com/macvk/vpnleaktest/main/vpnleaktest.sh
chmod +x vpnleaktest.sh
```

Run it:

```sh
./vpnleaktest.sh
```

### Python

Download the Python script:

```sh
curl -fLO https://raw.githubusercontent.com/macvk/vpnleaktest/main/vpnleaktest.py
chmod +x vpnleaktest.py
```

Run it:

```sh
./vpnleaktest.py
```

## Windows

Download the batch file:

```powershell
Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/macvk/vpnleaktest/main/vpnleaktest.bat -OutFile vpnleaktest.bat
```

Run it:

```bat
vpnleaktest.bat
```

## Go

Download the Go source and build it for the current platform:

```sh
curl -fLO https://raw.githubusercontent.com/macvk/vpnleaktest/main/vpnleaktest.go
go build -o vpnleaktest vpnleaktest.go
./vpnleaktest
```

Examples for other platforms:

```sh
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o vpnleaktest-linux-amd64 vpnleaktest.go
GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 go build -o vpnleaktest-darwin-arm64 vpnleaktest.go
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -o vpnleaktest-windows-amd64.exe vpnleaktest.go
```

## Docker

### Linux

```sh
docker run --rm --network host python:alpine sh -c 'apk add --no-cache iputils >/dev/null && wget -q -O- https://raw.githubusercontent.com/macvk/vpnleaktest/main/vpnleaktest.py | python'
```

### macOS and Windows

```sh
docker run --rm python:alpine sh -c 'apk add --no-cache iputils >/dev/null && wget -q -O- https://raw.githubusercontent.com/macvk/vpnleaktest/main/vpnleaktest.py | python'
```

## License

MIT
