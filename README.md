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

```
ansible-playbook run.yml --limit spudbox_dev --vault-password-file .vault_pass
```

### Vault

```
ansible-vault edit group_vars/all/vault.yml --vault-password-file .vault_pass
```

### Wireguard

Get client config 
```
qrencode -t ansiutf8 < clients/mikes-iphone/client.conf
```