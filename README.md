## SpudNet

### Supported OS

Ubuntu 24.04 LTS

### SSH Key

```
ssh-keygen -o -a 100 -t ed25519 -f ~/.ssh/spudnet
ssh-copy-id -i ~/.ssh/spudnet luds@192.168.0.42
```

### Run

First run requires `--ask-become-pass`.

Remember to generate a new Plex claim before the first run: https://plex.tv/claim

```
ansible-playbook run.yml --limit spudbox_dev --vault-password-file .vault_pass
```

### Post-Install

1. In Plex settings, add `plex.{{ domain }}` under Network -> "Custom server access URLs".

### Vault

```
ansible-vault edit group_vars/all/vault.yml --vault-password-file .vault_pass
```

### Wireguard

Get client config 
```
qrencode -t ansiutf8 < clients/mikes-iphone/client.conf
```

### Network Setup

Under `/etc/netplan/`:
```
network:
  version: 2
  ethernets:
    enp9s0:
      addresses:
        - 192.168.0.42/24
      routes:
        - to: default
          via: 192.168.0.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
      optional: false
```

```
sudo netplan apply
```