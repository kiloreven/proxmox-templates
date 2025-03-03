# Templates Generators for Proxmox

These scripts downloads a cloud image for a distro and sets up a cloud-init
configured template for that VM on your proxmox server.

## Distros Supported:
- Ubuntu 24.04 (EFI, Secure Boot enabled)
- Rocky Linux 9.5 (EFI, Secure Boot enabled)
- Arch Linux (EFI)

## Notes:

The configuration here is opinionated in that it:
- Uses EFI boot
- Enables a serial console
- Sets a default firewall on the VM allowing only incoming ping and ssh
- Uses local-lvm for storage
- Adds ssh keys from ~/.ssh/authorized_keys to the root user in the VM
- Resizes the disk to 32GB AFTER importing it, so the source image file is unmodified

## Usage:

- Copy one of the scripts to your PVE server
- Edit it to your liking, particularly the `VM_` variables
- Run as root to import a template to your installation
- Right click the template in your Proxmox UI, and select "Clone" to create a new server.
- Optional: If you need more space than 32GB, resize the disk image on the cloned VM before you start it as it will grow the partition on first boot.
- Start the new server (not the template!), and wait for the IP address to appear on the "Summary" for the VM


## TODO:
- [ ] Make more generic with reusable components
- [ ] Add command line arguments for `VM_` variables
- [ ] Add `recreate` option or something like that

## Stuff taken from:
- https://github.com/UntouchedWagons/Ubuntu-CloudInit-Docs
- https://forum.proxmox.com/threads/combining-custom-cloud-init-with-auto-generated.59008/page-3#post-428772
