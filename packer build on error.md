
Prepare first golden image
----------------------------------------------------------------------------------------------------------------
packer init .
packer build -var-file="values.pkrvars.hcl" .

./deploy-3nodes.sh

docker run --rm -it \
  --network host \
  -e ANSIBLE_HOST_KEY_CHECKING=False \
  --mount type=bind,source="$(pwd)/inventory/mycluster",dst=/inventory \
  --mount type=bind,source="${HOME}/.ssh/k8s_kubespray",dst=/keys/id_ed25519,readonly \
  quay.io/kubespray/kubespray:v2.29.0 bash -lc '
    set -e
    mkdir -p /root/.ssh
    cp /keys/id_ed25519 /root/.ssh/id_ed25519
    chmod 600 /root/.ssh/id_ed25519

    ansible -i /inventory/inventory.ini all -m ping --private-key /root/.ssh/id_ed25519
    ansible-playbook -i /inventory/inventory.ini --private-key /root/.ssh/id_ed25519 cluster.yml
  '
  
  
#Launch inside the container
mkdir -p /root/.ssh
cp /keys/id_ed25519 /root/.ssh/k8s_kubespray
chmod 600 /root/.ssh/id_ed25519

# quick connectivity tests
ssh -i /root/.ssh/k8s_kubespray -o StrictHostKeyChecking=no kube@192.168.56.11 "sudo -n true && echo OK"
ssh -i /root/.ssh/k8s_kubespray -o StrictHostKeyChecking=no kube@192.168.56.12 "sudo -n true && echo OK"
ssh -i /root/.ssh/k8s_kubespray -o StrictHostKeyChecking=no kube@192.168.56.13 "sudo -n true && echo OK"

# Checking cluster status without installing kubectl as root

If you can sudo on cp1 (your autoinstall sets NOPASSWD), do this from your host:

ssh -i ~/.ssh/k8s_kubespray kube@192.168.56.11 "sudo cat /etc/kubernetes/admin.conf" > admin.conf


Then install kubectl in your home (no sudo needed) and check:

mkdir -p ~/bin
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl ~/bin/
export PATH="$HOME/bin:$PATH"

export KUBECONFIG="$PWD/admin.conf"
kubectl get nodes -o wide
kubectl get pods -A



----------
packer build -on-error=abort -only=virtualbox-iso.k8s-base -var-file=k8s-base.pkrvars.hcl .

# controlplane
packer build -on-error=abort -only=virtualbox-ovf.k8s-node \
  -var "k8s_vm_name=k8s-controlplane" \
  -var "role=controlplane" \
  -var "control_ip=192.168.56.20" \
  -var "node_ip=192.168.56.20" \
  .

# worker01
packer build -on-error=abort -only=virtualbox-ovf.k8s-node \
  -var "k8s_vm_name=k8s-node01" \
  -var "role=worker" \
  -var "control_ip=192.168.56.20" \
  -var "node_ip=192.168.56.21" \
  .

# worker02
packer build -on-error=abort -only=virtualbox-ovf.k8s-node \
  -var "k8s_vm_name=k8s-node02" \
  -var "role=worker" \
  -var "control_ip=192.168.56.20" \
  -var "node_ip=192.168.56.22" \
  .

ssh -i ~/.ssh/id_ed25519_packer_gitlab packer@192.168.56.20





