# Push homelab-configs (WSL)

Your remote had an **old token baked into the URL**. That token is read-only. Fix:

## 1. Revoke old token
https://github.com/settings/tokens — delete/revoke any token you pasted in chat.

## 2. Create a **classic** token (easiest)
https://github.com/settings/tokens/new

- Note: `homelab-configs push`
- Expiration: 90 days (or your choice)
- Scopes: check **`repo`** (full control of private repositories)
- Generate → copy token (starts with `ghp_`)

Fine-grained tokens often fail here unless **Contents: Read and write** is set for `homelab-configs`.

## 3. Push (paste token when asked for password)

```bash
cd /mnt/c/Users/chris/homelab-site/homelab-configs
git remote set-url origin https://github.com/Chrismmaldonado/homelab-configs.git
git branch -M main
git push -u origin main
```

- Username: `Chrismmaldonado`
- Password: paste the **token** (`ghp_...`), not your GitHub password

## One-liner (token stays in shell history — use only if you accept that)

```bash
cd /mnt/c/Users/chris/homelab-site/homelab-configs
read -s -p "GitHub token: " GH_TOKEN; echo
git push https://Chrismmaldonado:${GH_TOKEN}@github.com/Chrismmaldonado/homelab-configs.git main
unset GH_TOKEN
git branch -u origin/main main 2>/dev/null || git push -u origin main
```

After success: https://github.com/Chrismmaldonado/homelab-configs
