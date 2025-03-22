## SpudNet

### Run

```
ansible-playbook run.yml --limit home_dev --vault-password-file .vault_pass
```

### Vault

```
ansible-vault edit group_vars/all/vault.yml --vault-password-file .vault_pass
```