## SpudNet

### Supported OS

Ubuntu 24.04 LTS

### SSH Key

```
ssh-keygen -o -a 100 -t ed25519 -f ~/.ssh/spudnet
ssh-copy-id ~/.ssh/spudnet luds@192.168.0.109
```

### Run

```
ansible-playbook run.yml --limit home_dev --vault-password-file .vault_pass
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