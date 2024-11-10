#!/bin/bash

# IP 주소를 변수로 정의합니다.
MASTER_IP="10.178.0.13"
NODE1_IP="10.178.0.9"
NODE2_IP="10.178.0.10"
NODE3_IP="10.178.0.11"

echo '======== [1] GCP 환경에서의 기본 설정 ========'
echo '======== [1-1] 패키지 업데이트 ========'
sudo apt-get update -y && sudo apt-get upgrade -y

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

echo '======== [5] kubeadm으로 클러스터 생성  ========'
echo '======== [5-1] 클러스터 초기화 (Pod Network 세팅) ========'
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=$MASTER_IP || { echo "kubeadm 명령이 실패했습니다."; exit 1; }

echo '======== [5-2] kubectl 사용 설정 ========'
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo '======== [5-3] join.sh 파일 생성 ========'
sudo kubeadm token create --print-join-command | sudo tee /home/ubuntu/join.sh

echo '======== [5-4] Pod Network 설치 (flannel) ========'
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml || echo "Pod Network 설치 오류 발생"

echo '======== [6] 쿠버네티스 편의기능 설치 ========'
echo '======== [6-1] kubectl 자동완성 기능 ========'
sudo apt-get install -y bash-completion
echo "source <(kubectl completion bash)" >> ~/.bashrc
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -F __start_kubectl k' >>~/.bashrc
source ~/.bashrc

echo '======== [6-2] Dashboard 설치 ========'
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.2.0/aio/deploy/recommended.yaml || echo "Dashboard 설치 오류 발생"

echo '======== [6-3] Metrics Server 설치 ========'
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml || echo "Metrics Server 설치 오류 발생"

echo '======== [7] Pod 상태 확인 ========'
kubectl get pods -A || echo "Pod 상태 확인 오류 발생"
