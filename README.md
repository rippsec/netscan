# netscan

A LOTL (Living Off The Land) network scanner written in pure Bash. No `nmap`, no `masscan`, no external dependencies — only built-ins and standard POSIX tools available on any minimal Linux system.

Built for environments where you can't install tools: CTF pivoting, restricted servers, containers, and post-exploitation recon.

## Features

- **Host discovery** — ICMP ping sweep across a subnet
- **Network port scan** — sweep all active hosts on a subnet for open ports
- **Single-host port scan** — targeted scan against one IP
- **Target list scan** — read IPs from a file and scan each one
- **Service detection** — basic banner grabbing on common ports
- **Interface listing** — show local network interfaces
- **Output to file** — save results with `-o`
- **IPv6 mode** (experimental)
- Configurable concurrency, timeout, and port range
- Handles `Ctrl+C` cleanly

All TCP probing uses `/dev/tcp` — no `nc` required unless doing banner grabs.

## Usage

```bash
bash netscan.sh [MODE] [OPTIONS]
```

### Modes

| Flag | Mode | Description |
|---|---|---|
| `-N` | Host discovery | Ping sweep to find active hosts on a subnet |
| `-P` | Network port scan | Port scan all hosts in a subnet range |
| `-p` | Single host port scan | Port scan a specific target IP |
| `-i` | Interfaces | List local network interfaces |

### Options

| Flag | Description | Default |
|---|---|---|
| `-t <IP>` | Target IP or subnet base (e.g. `192.168.1.0`) | — |
| `-T <file>` | Target list file (one IP per line) | — |
| `-r <ports>` | Port range or list | `1-65535` |
| `-R <range>` | Host range within subnet | `1-254` |
| `-c <n>` | Concurrent jobs | `50` |
| `-w <sec>` | Timeout in seconds | `2` |
| `-s` | Enable service/banner detection | off |
| `-o <file>` | Write output to file | stdout |
| `-v` | Verbose mode | off |
| `-q` | Quiet mode (suppress banner) | off |
| `-6` | IPv6 mode (experimental) | off |

### Port format

```
-r 80,443,8080        individual ports
-r 1-1000             range
-r 1-1000,8080,9000   mixed
```

## Examples

```bash
# Find active hosts on the subnet
bash netscan.sh -N -t 192.168.1.0

# Port scan a single host (common ports)
bash netscan.sh -p -t 192.168.1.1 -r 22,80,443,8080

# Scan all hosts in subnet, ports 1-10000, 200 threads
bash netscan.sh -P -t 192.168.1.0 -r 1-10000 -c 200

# Scan specific host range with banner grabbing
bash netscan.sh -P -t 192.168.1.0 -R 1-50 -r 22,80,443 -s

# Scan from a target list, save results
bash netscan.sh -T targets.txt -p -r 1-1000 -o results.txt

# Fast scan with short timeout
bash netscan.sh -p -t 10.10.10.5 -r 1-65535 -c 200 -w 1
```

## How it works

TCP port probing uses the Bash built-in `/dev/tcp` pseudo-device:

```bash
timeout $t bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null
```

This opens a TCP connection without any external tools. Banner grabbing falls back to `nc` only for known service ports (22, 80, 443, etc.) where a simple HTTP HEAD request can elicit a response.

Host discovery uses `ping -c 1 -W $timeout` with background jobs throttled by the `-c` concurrency setting.
