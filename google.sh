#!/bin/bash

RT_TABLE_ID="100"
RT_TABLE_NAME="rt_ens5"
INTERFACE="ens5"

PRIVATE_IP=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/1/ip" -H "Metadata-Flavor: Google")
GATEWAY=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/1/gateway" -H "Metadata-Flavor: Google")

counter=0
while [ $counter -lt 10 ]; do
    if ip link show ens5 | grep -q "state UP"; then
        break
    fi
    sleep 3
    ((counter++))
done

if ! grep -q "^${RT_TABLE_ID} ${RT_TABLE_NAME}$" /etc/iproute2/rt_tables; then
    echo "${RT_TABLE_ID} ${RT_TABLE_NAME}" | tee -a /etc/iproute2/rt_tables >/dev/null
fi

ip route add $GATEWAY src $PRIVATE_IP dev $INTERFACE table $RT_TABLE_NAME || true
ip route add default via $GATEWAY dev $INTERFACE table $RT_TABLE_NAME || true

ip rule add from $PRIVATE_IP/32 table $RT_TABLE_NAME || true
ip rule add to $PRIVATE_IP/32 table $RT_TABLE_NAME || true

cat > /etc/netplan/90-ens5-multi-route.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      routes:
        - to: $GATEWAY
          via: 0.0.0.0
          table: $RT_TABLE_ID
        - to: 0.0.0.0/0
          via: $GATEWAY
          table: $RT_TABLE_ID
      routing-policy:
        - from: $PRIVATE_IP
          table: $RT_TABLE_ID
        - to: $PRIVATE_IP
          table: $RT_TABLE_ID
EOF

netplan apply

echo "ens5 IP: $(ip -4 addr show ens5 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')"
ip route show table $RT_TABLE_NAME
ip rule list | grep $RT_TABLE_NAME

logger -t ens5-routing "Configuration completed. IP: $PRIVATE_IP, Gateway: $GATEWAY"
