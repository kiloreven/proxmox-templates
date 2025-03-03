#!/usr/bin/env bash

set -euo pipefail

VM_TEMPLATE_NAME="freebsd-14-2-template"
VM_IMAGE_URL=https://download.freebsd.org/ftp/releases/VM-IMAGES/14.2-RELEASE/amd64/Latest/FreeBSD-14.2-RELEASE-amd64-BASIC-CLOUDINIT.zfs.qcow2.xz
VM_IMAGE_CHECKSUMS_URL=$VM_IMAGE_URL.CHECKSUM

VM_STORAGE=local-lvm
VM_NET_BRIDGE=vmbr0
VM_ID=8142
VM_CORES=2
VM_MEM=2048
VM_DISK_SIZE=32G

VM_IMAGE_FN_COMPRESSED=$(basename "$VM_IMAGE_URL")
VM_IMAGE_FN=$(basename "$VM_IMAGE_URL" .xz)
VM_IMAGE_URL_BASE=$(dirname "$VM_IMAGE_URL")
VM_IMAGE_CHECKSUMS_URL=$VM_IMAGE_URL_BASE/CHECKSUM.SHA256



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
    curl --fail $VM_IMAGE_CHECKSUMS_URL | grep "$VM_IMAGE_FN_COMPRESSED" > $TDIR/SHA256SUMS
    echo "Downloading $VM_IMAGE_FN_COMPRESSED from $VM_IMAGE_URL"
    curl --fail -o $TDIR/$VM_IMAGE_FN_COMPRESSED $VM_IMAGE_URL
    echo "Checking that $VM_IMAGE_FN_COMPRESSED matches checksum"
    (cd $TDIR && sha256sum -c SHA256SUMS)
    unxz $TDIR/$VM_IMAGE_FN_COMPRESSED
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
EOF
fi


qm create $VM_ID --name "$VM_TEMPLATE_NAME" --ostype l26 \
    --memory $VM_MEM \
    --agent 1 \
    --bios ovmf --machine q35 --efidisk0 $VM_STORAGE:0,pre-enrolled-keys=1 \
    --cpu host --socket 1 --cores $VM_CORES \
    --vga serial0 --serial0 socket  \
    --net0 virtio,bridge=$VM_NET_BRIDGE,firewall=1
    
qm importdisk $VM_ID $VM_IMAGE_FN $VM_STORAGE
qm set $VM_ID --scsihw virtio-scsi-pci --virtio0 $VM_STORAGE:vm-$VM_ID-disk-1,discard=on,iothread=on
qm resize $VM_ID virtio0 $VM_DISK_SIZE
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
