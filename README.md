# Velveta Infra Prod

This repo manages only the Velveta production stack.

Included:
- prod Frappe compose
- prod Next.js compose
- prod-only nginx site config
- backup timer and restore flow
- production runner service template

This repo is intended for moving production onto a separate VPS.

## Inventory

Use:

```bash
/opt/velveta/infra-prod/inventories/prod/hosts.yml
```

Update `ansible_host` to the new production VPS before running the playbooks.

## Main Commands

Bootstrap:

```bash
cd /opt/velveta/infra-prod
ansible-playbook -i inventories/prod/hosts.yml playbooks/bootstrap.yml
```

Converge:

```bash
cd /opt/velveta/infra-prod
ansible-playbook -i inventories/prod/hosts.yml playbooks/server.yml
```

Restore prod:

```bash
cd /opt/velveta/infra-prod
ansible-playbook -i inventories/prod/hosts.yml playbooks/restore.yml
```
