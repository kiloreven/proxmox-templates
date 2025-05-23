#!/usr/bin/env bash

set -euo pipefail

VM_TEMPLATE_NAME="rocky-9-5-template"
VM_IMAGE_URL=https://dl.rockylinux.org/pub/rocky/9.5/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2
VM_IMAGE_CHECKSUMS_URL=$VM_IMAGE_URL.CHECKSUM

VM_STORAGE=local-lvm
VM_NET_BRIDGE=vmbr0
VM_ID=9001
VM_SOCKETS=1
VM_CORES=2
VM_MEM=2048

VM_SYSTEM_DISK_SIZE=20G
VM_STORAGE_DISK_SIZE=50G

VM_IMAGE_FN=$(basename "$VM_IMAGE_URL")


echo "Checking if ID $VM_ID already exists"
if qm show $VM_ID; then
    echo "ERROR: A VM or template with ID $VM_ID already exists"
    exit 2
else
    echo "OK: We can use ID $VM_ID, lets continue"
fi


if [ -f "$VM_IMAGE_FN" ]; then
    echo "OK: $VM_IMAGE_FN already downloaded"
else
    TDIR=$(mktemp -d)
    echo "Downloading SHA256 checksums from $VM_IMAGE_CHECKSUMS_URL"
    curl --fail -o $TDIR/SHA256SUMS $VM_IMAGE_CHECKSUMS_URL
    echo "Downloading $VM_IMAGE_FN from $VM_IMAGE_URL"
    curl --fail -o $TDIR/$VM_IMAGE_FN $VM_IMAGE_URL
    echo "Checking that $VM_IMAGE_FN matches checksum"
    (cd $TDIR && sha256sum -c SHA256SUMS)
    mv -v $TDIR/$VM_IMAGE_FN $VM_IMAGE_FN
fi


VM_TEMPLATE_SNIPPET=/var/lib/vz/snippets/$VM_TEMPLATE_NAME.yaml

if [ -f "$VM_TEMPLATE_SNIPPET" ]; then
    echo "$VM_TEMPLATE_SNIPPET already exists"
else
    echo "Generating runcmd script $VM_TEMPLATE_SNIPPET"
    mkdir -p /var/lib/vz/snippets
    cat << EOF | tee $VM_TEMPLATE_SNIPPET
#cloud-config
package_reboot_if_required: true
package_update: true
package_upgrade: true
packages:
- qemu-guest-agent
- dnf-automatic
- btop
- screen
- vim
runcmd:
- systemctl start qemu-guest-agent
- sed -i -r 's/apply_updates = false/apply_updates = true/' /etc/dnf/automatic.conf
- systemctl enable --now dnf-automatic.timer
EOF
fi


qm create $VM_ID --name "$VM_TEMPLATE_NAME" --ostype l26 \
    --memory $VM_MEM \
    --agent 1 \
    --bios ovmf --machine q35 --efidisk0 $VM_STORAGE:0,efitype=4m,pre-enrolled-keys=1 \
    --cpu host --socket $VM_SOCKETS --cores $VM_CORES \
    --vga serial0 --serial0 socket  \
    --net0 virtio,bridge=$VM_NET_BRIDGE,firewall=1
    
qm importdisk $VM_ID $VM_IMAGE_FN $VM_STORAGE
qm set $VM_ID --scsihw virtio-scsi-pci --virtio0 $VM_STORAGE:vm-$VM_ID-disk-1,discard=on,iothread=on
qm set $VM_ID --scsihw virtio-scsi-pci --virtio1 $VM_STORAGE:vm-$VM_ID-disk-2,discard=on,iothread=on
qm resize $VM_ID virtio0 $VM_SYSTEM_DISK_SIZE
qm resize $VM_ID virtio1 $VM_STORAGE_DISK_SIZE
qm set $VM_ID --boot order=virtio0
qm set $VM_ID --ide2 $VM_STORAGE:cloudinit
qm set $VM_ID --tpmstate0 file=$VM_STORAGE:0,size=4M,version=v2.0
cat << EOF | tee /etc/pve/firewall/$VM_ID.fw
[OPTIONS]

enable: 1
policy_in: DROP
policy_out: ACCEPT

[RULES]

IN SSH(ACCEPT) 
IN Ping(ACCEPT)

EOF

qm set $VM_ID --cicustom "vendor=local:snippets/$VM_TEMPLATE_NAME.yaml"
qm set $VM_ID --ciuser root
qm set $VM_ID --sshkeys ~/.ssh/authorized_keys
qm set $VM_ID --ipconfig0 ip=dhcp

qm template $VM_ID
