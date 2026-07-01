# Security

This repository contains **sanitized reference configs only**. No production secrets belong here.

## If you find a secret

If you believe a token, password, or private key was committed by mistake:

1. **Do not** open a public issue with the secret contents
2. Contact me via [LinkedIn](https://www.linkedin.com/in/christopher-maldonado-86317228b/)
3. I will rotate credentials and rewrite history if needed

## Public terminal scope

The live terminal on [christopher.isageek.net](https://christopher.isageek.net) is intentionally limited:

- Read-only command whitelist (`ls`, `cat`, `tree`, etc.)
- Path jail: `/opt/stacks` and Minecraft config only
- Blocked: `.env`, keys, certs, databases, most dotfiles
- Output redaction for IPs, emails, tokens
- Rate limits and session timeout
- Commands audit-logged on the host (not published)

Do not attempt to bypass these controls. Report responsible disclosure issues privately.

## Production secrets location

Live credentials (Cloudflare API, tunnel tokens, etc.) are stored **outside** deployed site paths on the homelab host, not in this repo.
