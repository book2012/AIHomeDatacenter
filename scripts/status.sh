#!/bin/bash
echo "AI Home Datacenter Status"
echo "========================="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
