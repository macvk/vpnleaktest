# VPN Leak Test

These command-line clients run the network checks used by the
[bash.ws VPN test](https://bash.ws/vpn-leak-test). They detect public IPv4 and
IPv6 addresses, check for DNS leaks, scan common ports, check IP blacklists,
and report the server-side connection analysis.

## Requirements

- Python 3.6 or newer for `vpnleaktest.py`
- A POSIX shell, `curl`, and `ping` for `vpnleaktest.sh`
- Windows PowerShell, `curl.exe`, and `ping.exe` for `vpnleaktest.bat`
- `curl` only when `--interface` is used by the Python client
- Go only when building `vpnleaktest.go`

## Usage

Run the Python client:

```sh
python vpnleaktest.py
```

On Linux and macOS, run the standalone shell client:

```sh
./vpnleaktest.sh
```

On Windows, run the standalone batch client:

```bat
vpnleaktest.bat
```

The Go client is standalone after compilation:

```sh
go build vpnleaktest.go
./vpnleaktest
```

Use a specific interface:

```sh
python vpnleaktest.py --interface eth0
```

Print a one-line monitoring result:

```sh
python vpnleaktest.py --short
```

Print structured output:

```sh
python vpnleaktest.py --json
```

Run a client with `--help` to see all options.

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
