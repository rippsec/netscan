#!/bin/bash

# netscan v0.2, Author: Rafa Aka Rippsec (enhanced)
# A LOTL (Living Off The Land) network scanner for minimal environments

function ctrl_c(){
  echo -e "\n[!] Exiting..."
  kill -- -$$ 2>/dev/null
  exit 1
}
trap ctrl_c INT

function banner(){
  echo '
  _  __    __  ____            
  / |/ /__ / /_/ __/______ ____ 
 /    / -_) __/\ \/ __/ _ `/ _ \
/_/|_/\__/\__/___/\__/\_,_/_//_/
 v0.2 - LOTL Network Scanner
 '
}

function help_panel(){
  if command -v hostname &>/dev/null && hostname -I &>/dev/null; then 
    ip_addr_help="$(hostname -I 2>/dev/null | grep -oP '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}'|head -n1)"
  else
    ip_addr_help="192.168.1.1"
  fi

  echo -e "\n[i] Usage: $0 [OPTIONS]\n"
  echo -e "TARGET SPECIFICATION:"
  echo -e "  -t) Target IP/Network: $ip_addr_help"
  echo -e "  -T) Target list file (one IP per line)"
  echo -e "\nSCAN MODES:"
  echo -e "  -N) Network scan (find active hosts): $0 -N -t $ip_addr_help"
  echo -e "  -P) Port scan all active hosts: $0 -P -t $ip_addr_help"
  echo -e "  -p) Port scan single host: $0 -p -t $ip_addr_help"
  echo -e "  -s) Service detection (banner grabbing): $0 -p -t $ip_addr_help -s"
  echo -e "\nOPTIONS:"
  echo -e "  -r) Port range (default 1-65535): $0 -p -t $ip_addr_help -r 80,443,8080"
  echo -e "  -R) Network range (default 1-254): $0 -N -t $ip_addr_help -R 1-20"
  echo -e "  -c) Concurrent jobs (default 50): $0 -P -t $ip_addr_help -c 100"
  echo -e "  -w) Timeout in seconds (default 2): $0 -N -t $ip_addr_help -w 5"
  echo -e "  -o) Output file (default: stdout)"
  echo -e "  -i) Show local interfaces: $0 -i"
  echo -e "  -v) Verbose mode"
  echo -e "  -q) Quiet mode (suppress banners)"
  echo -e "  -6) IPv6 mode (experimental)"
  echo -e "\nPORT FORMAT EXAMPLES:"
  echo -e "  -r 80,443,8080        (specific ports)"
  echo -e "  -r 1-1000             (port range)"
  echo -e "  -r 1-1000,8080,9000  (mixed format)"
  echo -e "\nEXAMPLES:"
  echo -e "  bash $0 -p -t 192.168.1.1 -r 22,80,443 -w 1"
  echo -e "  bash $0 -P -t 192.168.1.0 -R 1-254 -r 1-10000 -c 200" 
  echo -e "  bash $0 -T targets.txt -p -r 1-1000 -o results.txt"
}

function interfaces(){
  echo "--- Network Interfaces ---"
  if command -v ip &>/dev/null; then
    ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | while read ip; do
      ((ifacenum++))
      echo -e "[$ifacenum] $ip"
    done
  elif command -v ifconfig &>/dev/null; then
    ifconfig | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | while read ip; do
      ((ifacenum++))
      echo -e "[$ifacenum] $ip"
    done
  else
    hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^$' | while read ip; do
      ((ifacenum++))
      echo -e "[$ifacenum] $ip"
    done
  fi
  echo "--- Finished ---"
}

function parse_port_list() {
  local port_list="$1"
  local ports=""
  
  IFS=',' read -ra PORT_PARTS <<< "$port_list"
  for part in "${PORT_PARTS[@]}"; do
    if [[ $part =~ ^[0-9]+$ ]]; then
      ports="$ports $part"
    elif [[ $part =~ ^([0-9]+)-([0-9]+)$ ]]; then
      for ((p=${BASH_REMATCH[1]}; p<=${BASH_REMATCH[2]}; p++)); do
        ports="$ports $p"
      done
    fi
  done
  echo "$ports"
}

function grab_banner() {
  local host=$1
  local port=$2
  local timeout=$3
  
  # Common service banners
  case $port in
    21|22|23|25|80|110|143|443|993|995|3306|5432|6379|27017)
      local banner=$(timeout $timeout echo -e "HEAD / HTTP/1.0\r\n\r\n" 2>/dev/null | nc -w $timeout $host $port 2>/dev/null | head -n1)
      if [ -n "$banner" ]; then
        echo -e "[+] $host:$port - $banner"
      else
        echo -e "[+] $host:$port"
      fi
      ;;
    *)
      echo -e "[+] $host:$port"
      ;;
  esac
}

function portscan(){
  local network_base="${network%.*}"
  local host_range=$(seq ${network_range//-/ } 2>/dev/null)
  
  if [ -z "$host_range" ]; then
    host_range=$(seq 1 254)
  fi
  
  local ports=$(parse_port_list "$port_range")
  local port_count=$(echo $ports | wc -w)
  local total_scans=$(echo "$host_range" | wc -w)
  
  [ "$verbose" = true ] && echo -e "\n[*] Scanning $total_scans hosts × $port_count ports = $((total_scans * port_count)) probes"
  [ "$verbose" = true ] && echo -e "[*] Using $concurrent_jobs concurrent jobs\n"
  
  echo -e "\n--- PORT SCAN: $network_base.x:$port_range ---"
  
  local host_pids=""
  for host in $host_range; do
    (
      local target_ip="$network_base.$host"
      if ping -c 1 -W $time_out $target_ip >/dev/null 2>&1; then
        [ "$verbose" = true ] && echo -e "[*] Scanning $target_ip (up)"
        for port in $ports; do
          (
            if timeout $time_out bash -c "echo >/dev/tcp/$target_ip/$port" 2>/dev/null; then
              if [ "$service_detection" = true ]; then
                grab_banner "$target_ip" "$port" "$time_out"
              else
                echo -e "[+] $target_ip:$port"
              fi
            fi
          ) &
          
          # Limit concurrent jobs
          while [ $(jobs -r | wc -l) -ge $concurrent_jobs ]; do
            sleep 0.01
          done
        done
        wait
      elif [ "$verbose" = true ]; then
        echo -e "[*] $target_ip (down)"
      fi
    ) &
    
    # Limit host concurrency
    host_pids="$host_pids $!"
    while [ $(echo $host_pids | wc -w) -ge 10 ]; do
      sleep 0.1
      for pid in $host_pids; do
        if ! kill -0 $pid 2>/dev/null; then
          host_pids=$(echo $host_pids | sed "s/\b$pid\b//")
        fi
      done
    done
  done
  
  wait
  echo "--- Finished scan ---"
}

function hostscan(){
  local network_base="${network%.*}"
  local host_range=$(seq ${network_range//-/ } 2>/dev/null)
  
  if [ -z "$host_range" ]; then
    host_range=$(seq 1 254)
  fi
  
  echo -e "\n--- HOST DISCOVERY: $network_base.x ---"
  
  local count=0
  for host in $host_range; do
    (
      local target_ip="$network_base.$host"
      if timeout $time_out ping -c 1 -W $time_out $target_ip >/dev/null 2>&1; then
        # Try to get hostname if possible
        local hostname=""
        if command -v host &>/dev/null; then
          hostname=$(host $target_ip 2>/dev/null | grep 'domain name pointer' | awk '{print $NF}' | sed 's/\.$//')
        fi
        if [ -n "$hostname" ]; then
          echo -e "[+] Active Host: $target_ip ($hostname)"
        else
          echo -e "[+] Active Host: $target_ip"
        fi
        ((count++))
      fi
    ) &
    
    # Limit concurrency
    while [ $(jobs -r | wc -l) -ge $concurrent_jobs ]; do
      sleep 0.01
    done
  done
  
  wait
  echo -e "\n--- Found $count active hosts ---"
}

function target_portscan(){
  local ports=$(parse_port_list "$port_range")
  local port_count=$(echo $ports | wc -w)
  
  [ "$verbose" = true ] && echo -e "\n[*] Scanning $target on $port_count ports\n"
  echo -e "\n--- PORT SCAN: $target:$port_range ---"
  
  for port in $ports; do
    (
      if timeout $time_out bash -c "echo >/dev/tcp/$target/$port" 2>/dev/null; then
        if [ "$service_detection" = true ]; then
          grab_banner "$target" "$port" "$time_out"
        else
          echo -e "[+] $target:$port"
        fi
      fi
    ) &
    
    # Limit concurrency
    while [ $(jobs -r | wc -l) -ge $concurrent_jobs ]; do
      sleep 0.01
    done
  done
  
  wait
  echo "--- Finished scan ---"
}

function target_list_scan() {
  if [ ! -f "$target_file" ]; then
    echo -e "[!] Target file not found: $target_file"
    exit 1
  fi
  
  echo -e "\n--- SCANNING TARGETS FROM $target_file ---"
  while IFS= read -r target_ip; do
    if [ -n "$target_ip" ] && [[ $target_ip =~ ^[0-9] ]]; then
      echo -e "\n[*] Scanning $target_ip"
      local old_target="$target"
      target="$target_ip"
      target_portscan
      target="$old_target"
    fi
  done < "$target_file"
}

# Default values
port_range="1-65535"
network_range="1-254"
time_out="2"
concurrent_jobs=50
service_detection=false
verbose=false
quiet=false
ipv6=false

# Parse command-line options
while getopts "t:T:NPpSR:r:sc:w:o:ivhq6" arg; do
  case $arg in
    t) target=$OPTARG ;;
    T) target_file=$OPTARG ;;
    N) flag_N=true ;;
    P) flag_P=true ;;
    p) flag_p=true ;;
    s) service_detection=true ;;
    S) service_detection=true ;; # Alias for -s
    r) port_range=$OPTARG ;;
    R) network_range=$OPTARG ;;
    c) concurrent_jobs=$OPTARG ;;
    w) time_out=$OPTARG ;;
    o) output_file=$OPTARG ;;
    i) flag_i=true ;;
    v) verbose=true ;;
    q) quiet=true ;;
    6) ipv6=true ;;
    h) banner; help_panel; exit 0 ;;
  esac
done

# Extract network prefix
if [ -n "$target" ]; then
  if [[ $target =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    network="${target%.*}"
  elif [[ $target =~ ^([0-9]{1,3}\.){2}[0-9]{1,3}$ ]]; then
    network="$target.0"
  else
    network="$target"
  fi
fi

# Redirect output if specified
if [ -n "$output_file" ]; then
  exec > >(tee -a "$output_file")
fi

# Show banner
if [ "$quiet" = false ]; then
  banner
fi

# IPv6 warning
if [ "$ipv6" = true ]; then
  echo -e "[!] IPv6 mode is experimental and may not work in all environments"
fi

# Validate numeric values
if ! [[ "$concurrent_jobs" =~ ^[0-9]+$ ]] || [ "$concurrent_jobs" -lt 1 ]; then
  concurrent_jobs=50
fi

if ! [[ "$time_out" =~ ^[0-9]+\.?[0-9]*$ ]] || [ "$(echo "$time_out < 0.1" | bc)" -eq 1 ]; then
  time_out=2
fi

# Main execution logic
if [[ -n "$flag_N" && -n "$network" ]]; then
  hostscan
elif [[ -n "$flag_P" && -n "$network" ]]; then
  portscan
elif [[ -n "$flag_p" && -n "$target" ]]; then
  target_portscan
elif [[ -n "$target_file" ]]; then
  target_list_scan
elif [[ -n "$flag_i" ]]; then
  interfaces
else
  help_panel
  exit 1
fi
