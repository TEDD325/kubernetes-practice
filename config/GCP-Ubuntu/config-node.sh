#!/bin/bash

# IP 주소를 변수로 정의합니다.
MASTER_IP="10.178.0.13"
NODE1_IP="10.178.0.9"
NODE2_IP="10.178.0.10"
NODE3_IP="10.178.0.11"

echo '======== [1] Ubuntu 기본 설정 ========'
echo '======== [1-1] 패키지 업데이트 ========'
# 현재 업데이트 시 VM 기동이 안되는 이슈가 있어, 업데이트는 하지 않습니다.
# 필요한 경우에만 업데이트를 수행합니다.

echo '======== [1-2] 타임존 설정 ========'
sudo timedatectl set-timezone Asia/Seoul

echo '======== [1-3] [WARNING FileExisting-tc]: tc not found in system path 로그 관련 업데이트 ========'
sudo apt-get install -y iproute2

echo '======= [1-4] hosts 설정 =========='
cat << EOF | sudo tee -a /etc/hosts
$MASTER_IP k8s-master
$NODE1_IP k8s-node1
$NODE2_IP k8s-node2
$NODE3_IP k8s-node3
EOF

echo '======== [2] kubeadm 설치 전 사전작업 ========'
echo '======== [2-1] 방화벽 해제 ========'
sudo ufw disable || echo "GCP에서는 ufw가 비활성화되어 있습니다."

echo '======== [2-2] Swap 비활성화 ========'
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

echo '======== [3] 컨테이너 런타임 설치 ========'
echo '======== [3-1] 컨테이너 런타임 설치 전 사전작업 ========'
echo '======== [3-1-1] iptable 세팅 ========'
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

echo '======== [3-2] 컨테이너 런타임 (containerd 설치) ========'
sudo apt-get update -y && sudo apt-get install -y containerd

sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml

sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd

echo '======== [4] Kubernetes 설치를 위한 GPG 키 및 리포지토리 설정 ========'
echo '======== [4-1] 기존의 GPG 키 및 리포지토리 제거 ========'
sudo rm -f /etc/apt/keyrings/kubernetes-archive-keyring.gpg
sudo rm -f /etc/apt/sources.list.d/kubernetes.list

echo '======== [4-2] 새로운 GPG 키 추가 및 리포지토리 설정 ========'
sudo apt-get update && sudo apt-get install -y curl gnupg apt-transport-https ca-certificates

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

echo '======== [4-3] kubelet, kubeadm, kubectl 패키지 설치 및 고정 ========'
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

sudo systemctl enable --now kubelet

echo '======== [5] 노드가 클러스터에 참여할 준비가 되었습니다 ========'
echo '마스터 노드에서 생성된 join.sh 파일을 실행하여 클러스터에 참여하세요.'