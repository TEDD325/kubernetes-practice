#!/bin/bash

echo '======== [1] Ubuntu 기본 설정 ========'
echo '======== [1-1] 패키지 업데이트 ========'
# 현재 업데이트 시 VM 기동이 안되는 이슈가 있어, 업데이트는 하지 않습니다.

echo '======== [1-2] 타임존 설정 ========'
sudo timedatectl set-timezone Asia/Seoul

echo '======== [1-3] [WARNING FileExisting-tc]: tc not found in system path 로그 관련 업데이트 ========'
sudo apt-get install -y iproute2

# GCP 내부 IP로 설정
echo '======= [1-4] hosts 설정 =========='
cat << EOF | sudo tee -a /etc/hosts
10.178.0.5 k8s-master
10.178.0.6 k8s-node1
10.178.0.7 k8s-node2
EOF

echo '======== [2] kubeadm 설치 전 사전작업 ========'
echo '======== [2-1] 방화벽 해제 ========'
sudo ufw disable || echo "GCP에서는 ufw가 비활성화되어 있습니다."

echo '======== [2-2] Swap 비활성화 ========'
sudo swapoff -a && sudo sed -i '/ swap / s/^/#/' /etc/fstab

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
echo '======== [3-2-1] containerd 패키지 설치 (옵션 2) ========'
echo '======== [3-2-1-1] Docker 리포지토리 추가 ========'
sudo apt-get update -y && sudo apt-get install -y ca-certificates curl gnupg lsb-release
sudo mkdir -m 0755 -p /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  \$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo '======== [3-2-1-2] containerd 설치 ========'
sudo apt-get update -y && sudo apt-get install -y containerd.io
sudo systemctl daemon-reload
sudo systemctl enable --now containerd

echo '======== [3-3] 컨테이너 런타임: CRI 활성화 ========'
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


echo '======== [4-4] GCP 특이 에러 조정 ========'
ARCH=$(dpkg --print-architecture)
CODENAME=$(lsb_release -cs)
echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo rm -f /etc/apt/sources.list.d/kubernetes.list
sudo rm -f /etc/apt/sources.list.d/kubernetes.list.save

sudo sed -i '/kubernetes/d' /etc/apt/sources.list

sudo apt-get update && sudo apt-get install -y ca-certificates curl
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

sudo apt-get update
sudo apt-get install -y containerd

echo '======== [5] 노드가 클러스터에 참여할 준비가 되었습니다 ========'
echo '마스터 노드에서 생성된 join.sh 파일을 실행하여 클러스터에 참여하세요.'