#!/bin/bash
set -e

echo "=== Setting up Fail2ban for Velveta Security (Nginx & Custom SSH Port 4383) ==="

# 1. Install fail2ban if not present
if ! command -v fail2ban-client &> /dev/null; then
    echo "Installing Fail2ban..."
    apt-get update -qq
    apt-get install -y fail2ban
fi

# Ensure log directories exist
mkdir -p /opt/velveta/logs/nginx/
mkdir -p /opt/velveta/logs/fail2ban/
touch /opt/velveta/logs/fail2ban/banned.log /opt/velveta/logs/fail2ban/unbanned.log /opt/velveta/logs/nginx/suspicious.log

# 2. Custom Action for Logging Banned and Unbanned IPs to /opt/velveta/logs/fail2ban/
echo "Creating Fail2ban action: velveta-logger..."
cat << 'EOF' > /etc/fail2ban/action.d/velveta-logger.conf
[Definition]
actionstart =
actionstop =
actioncheck =
actionban = echo "[$(date '+%%Y-%%m-%%d %%H:%%M:%%S')] BANNED  | Jail: <name> | IP: <ip> | Failures: <failures>" >> /opt/velveta/logs/fail2ban/banned.log
actionunban = echo "[$(date '+%%Y-%%m-%%d %%H:%%M:%%S')] UNBANNED| Jail: <name> | IP: <ip>" >> /opt/velveta/logs/fail2ban/unbanned.log
EOF

# 3. Custom SSH Jail (Port 22 & Custom Port 4383)
echo "Creating Fail2ban SSH jail: /etc/fail2ban/jail.d/sshd.local..."
cat << 'EOF' > /etc/fail2ban/jail.d/sshd.local
[sshd]
enabled = true
port    = ssh,4383
action  = iptables-multiport[name=sshd, port="ssh,4383", protocol=tcp]
          velveta-logger[name=sshd]
EOF

# 4. Filter: Exploit Probes & Proxy/SOCKS Scans
echo "Creating Fail2ban filter: nginx-exploit-scan..."
cat << 'EOF' > /etc/fail2ban/filter.d/nginx-exploit-scan.conf
[Definition]
failregex = <HOST> (404|400|403) ".*(/\.env|/\?\.env|/env/\.env|/app/\.env|/api/\.env|/backend/\.env|/config/\.env|/admin/\.env|/src/\.env|/settings/\.env|/server/\.env|/private/\.env|/storage/\.env|/vendor/phpunit|/phpunit|/cgi-bin|/wp-admin|eval-stdin|\.aws|\.git|CONNECT|\x04\x01|\x05\x01).*"
ignoreregex =
EOF

# 5. Filter: Generic 404/400 High Frequency Scans
echo "Creating Fail2ban filter: nginx-404-scan..."
cat << 'EOF' > /etc/fail2ban/filter.d/nginx-404-scan.conf
[Definition]
failregex = <HOST> (404|400|403) ".*"
ignoreregex =
EOF

# 6. Nginx Jail Configuration
echo "Creating Fail2ban jail: /etc/fail2ban/jail.d/nginx-security.conf..."
cat << 'EOF' > /etc/fail2ban/jail.d/nginx-security.conf
[nginx-exploit-scan]
enabled  = true
port     = http,https
filter   = nginx-exploit-scan
logpath  = /opt/velveta/logs/nginx/access.log
maxretry = 3
findtime = 3600
bantime  = 86400
action   = iptables-multiport[name=%(__name__)s, port="%(port)s", protocol="%(protocol)s", chain="%(chain)s"]
           velveta-logger[name=%(__name__)s]

[nginx-404-scan]
enabled  = true
port     = http,https
filter   = nginx-404-scan
logpath  = /opt/velveta/logs/nginx/access.log
maxretry = 15
findtime = 60
bantime  = 3600
action   = iptables-multiport[name=%(__name__)s, port="%(port)s", protocol="%(protocol)s", chain="%(chain)s"]
           velveta-logger[name=%(__name__)s]
EOF

# 7. Restart and enable fail2ban
echo "Restarting fail2ban service..."
systemctl enable fail2ban
systemctl restart fail2ban

echo "=== Fail2ban Setup Complete ==="
fail2ban-client status
