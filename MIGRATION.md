# Prod Migration Runbook

Use this runbook when moving Velveta production to a new VPS.

## 1. Prepare the new server

Install Docker:

```bash
cd /opt/velveta/infra-prod
sudo ./scripts/install-docker.sh
```

Install Ansible on the control node:

```bash
cd /opt/velveta/infra-prod
./scripts/install-ansible.sh
```

## 2. Update the inventory

Edit:

```bash
/opt/velveta/infra-prod/inventories/prod/hosts.yml
```

Set:
- `ansible_host` to the new VPS IP
- `ansible_user` to the SSH user, usually `root`
- `ansible_ssh_private_key_file` if the default SSH key should not be used

## 3. Bootstrap the target server

```bash
cd /opt/velveta/infra-prod
ansible-playbook playbooks/bootstrap.yml
```

## 4. Converge the target server

```bash
cd /opt/velveta/infra-prod
ansible-playbook playbooks/server.yml
```

## 5. Restore production

Default source:

```bash
/opt/velveta/backups/latest
```

Run the restore:

```bash
cd /opt/velveta/infra-prod
ansible-playbook playbooks/restore.yml
```

Or use a specific backup:

```bash
cd /opt/velveta/infra-prod
ansible-playbook -e restore_backup_dir=/opt/velveta/backups/20260315_234005 playbooks/restore.yml
```

## 6. Verify after restore

Check:
- `http://<server>:8080`
- `http://<server>:8082`
- `docker ps`
- `docker logs frappe-backend-1`
- `docker logs nextjs-web-1`

## Notes

- `restore.yml` is destructive for the target production server.
- This repo restores only production services.
- Development services are intentionally excluded.
