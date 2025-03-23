## SpudNet

### Supported OS

Ubuntu 24.04 LTS

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