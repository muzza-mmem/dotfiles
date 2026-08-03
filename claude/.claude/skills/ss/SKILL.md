---
name: ss
description: Use when inspecting or debugging a portal server environment over SSH — "/ss dev", "check the uat server", "look at the prod logs", "docker logs on test", "is the container up on dev", "check the config/secrets on uat", "why is x failing on the server". Connects via the `ss <env>` script (dev/test/uat/prod) in READ-ONLY debug mode: gathers evidence, reads it critically, and NEVER performs a fix, restart, delete, or any other write action without explicit per-action consent.
---

# ss — read-only server debugging (dev / test / uat / prod)

Remote access to the portal environments through the `ss` wrapper. This skill is
for **diagnosis only**. You look, you read, you reason, you report. You do not
change anything on a server unless the user explicitly tells you to, for that
specific action, after you have shown them the exact command.

## The prime rule

> **Read-only by default. Every write is gated by explicit consent.**

Diagnosing is not fixing. Finding the cause does not authorise the cure.
"Check the test server" is a request to *look*, never a licence to *act*.
When you find the problem, say what you'd do and **stop**, then wait.

## The `ss` script

```
ss <env>                        # interactive shell (avoid in agent use)
ss dev uptime                   # run a command, stream output, exit
ss uat -- df -h /var            # everything after -- is the remote command
ss test -c 'cd /var/docker && ls -l'   # quoted string, shell metachars OK
ss prod -t 'sudo journalctl -u foo'    # -t forces a pty (needed for sudo prompts)
```

Environments: `dev` → pcportal-dev · `test` → 10.64.96.41 · `uat` → 10.64.96.38 ·
`prod` → pcportal.mml.com.au

Notes that matter in practice:

- The command is handed to the **remote** login shell verbatim, so pipes, globs
  and redirections evaluate on the server. Quote locally so your own shell
  doesn't eat them.
- **Always run one-shot commands** (`ss <env> <cmd>`), never a bare interactive
  `ss <env>` — an interactive shell will hang the tool call.
- `ss` requires the VPN. If a connection fails, say so and stop; don't retry in
  a loop or start "fixing" networking.
- `**` needs globstar remotely — use `find` for recursive matching.
- Always **bound the output**: `--tail`, `--since`, `head`, `grep`. Never dump an
  unbounded log file into the conversation.

## Allowed without asking (read-only)

These are safe on every environment:

- `docker ps -a`, `docker inspect <c>`, `docker logs --tail N --since T <c>`
- `docker compose config`, `docker compose ps` (config is read-only; `up`/`down` are NOT)
- `docker stats --no-stream`, `docker images`, `docker network ls|inspect`,
  `docker volume ls|inspect`
- Reading repo/config files: `ls -l`, `cat`, `head`, `tail`, `grep`, `find`,
  `stat`, `diff` under `/var/docker` and similar
- Host state: `uptime`, `df -h`, `free -m`, `top -bn1`, `ss -ltnp`, `systemctl status`,
  `journalctl --no-pager -n N` (read-only queries)
- `git status`, `git log`, `git diff`, `git show` in a remote repo — **not** pull,
  checkout, reset, clean or stash
- Existence/shape checks on secrets: confirm a var **is set** and looks right in
  form. Print the key, not the value — see Secrets below.

## Requires explicit consent, every single time

Never run any of these off your own judgement, not even when the fix is obvious
and one word long:

- `docker restart|stop|start|kill|rm|rmi|prune|exec` (any `exec` that isn't a pure read),
  `docker compose up|down|restart|pull|build`
- Any write to the filesystem: `rm`, `mv`, `cp`, `>`, `>>`, `tee`, `chmod`, `chown`,
  `mkdir`, `truncate`, editors
- `systemctl start|stop|restart|reload|enable|disable`, `kill`, `pkill`
- Package/deploy actions: `apt`, `yum`, `npm i`, deploy or migration scripts
- Any DB write, migration, or destructive query
- `git pull|checkout|reset|clean|stash|merge`
- Anything under `sudo` that isn't a plain read

**How to ask:** state the diagnosis, show the exact command(s) you would run,
name the environment and the blast radius, then wait for a clear yes. A user
saying "that sounds right" or "makes sense" is **not** consent to execute.
Consent is per-action and does not carry over to the next command, the next
container, or the next environment.

## UAT and PROD — extra caution

`uat` and `prod` are shared, business-facing environments.

1. **No passwordless sudo on uat or prod.** A `sudo` command will sit waiting on a
   password prompt. Do not attempt sudo there. If a diagnosis genuinely needs it,
   hand the user the exact command to run themselves — suggest they type
   `! ss prod -t '<cmd>'` in the prompt so the output lands in the session.
   Never try to supply, guess, or cache a password.
2. **Prod is production.** Real users, real data. Every action is read-only unless
   the user has, in this conversation, explicitly authorised that exact command on
   prod. "Do it on prod" said about one container does not extend to another.
3. **Say the environment out loud.** Before any prod or uat command, name the env
   in your message so it can't be mistaken for dev.
4. **Never let a dev/test habit leak upward.** Approval to restart something on dev
   is approval for *dev only*. Re-ask for uat, re-ask again for prod.
5. **Keep the footprint small on uat/prod** — bounded log windows, no heavy scans,
   no `find /` sweeps, nothing that loads a live box.
6. **Don't touch anything you weren't asked about.** No opportunistic cleanup, no
   "while I'm here" tidying, no pruning dangling images.

Dev and test are more forgiving, but the consent rule still applies in full —
the difference is the tone of the warning, not the rule.

## Typical investigations

**Container logs**
```
ss <env> 'docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"'
ss <env> 'docker logs --tail 200 --since 1h <container> 2>&1'
```
Read them **critically**: find the *first* error in the causal chain, not the
loudest or last one; check timestamps against the reported symptom; watch for
restart loops (`Restarting (1) 3 seconds ago`), OOM kills, and exit codes.

**Docker repo / compose files** (usually `/var/docker`)
```
ss <env> 'ls -la /var/docker'
ss <env> 'cat /var/docker/<stack>/docker-compose.yml'
ss <env> 'cd /var/docker/<stack> && docker compose config'
```
`docker compose config` shows the *resolved* config after env interpolation —
that's what actually applies, and it's where wiring bugs surface.

**Wiring / connectivity**
```
ss <env> 'docker network inspect <net> --format "{{json .Containers}}"'
ss <env> 'docker inspect <c> --format "{{json .NetworkSettings.Networks}}"'
ss <env> 'ss -ltnp'
```
Check published vs internal ports, service names used as hostnames, whether the
containers that need each other share a network, and healthcheck status.

**Config and secrets — never print values**
```
ss <env> 'docker inspect <c> --format "{{range .Config.Env}}{{println .}}{{end}}" | cut -d= -f1'
ss <env> 'docker exec <c> printenv | sed "s/=.*/=<set>/" | sort'
ss <env> 'ls -l /var/docker/<stack>/.env && grep -c . /var/docker/<stack>/.env'
```
Confirm a secret is **present** and has plausible shape (length, prefix), never
its value. Do not cat a `.env`, key, or certificate into the conversation. If you
must compare two environments, compare key sets and value *lengths/hashes*, not
values.

## Reading critically

The point of this skill is judgement, not command execution.

- Distinguish **evidence** from **inference**. Say which is which: "the log shows
  X" vs "which suggests Y".
- Corroborate before concluding — one error line is a hint, not a root cause.
  Cross-check logs against container state, config, and connectivity.
- Note what you did **not** check, and what you couldn't check (e.g. blocked by
  sudo on prod).
- If the evidence is ambiguous, say so. Don't manufacture a tidy story.
- Beware stale evidence: check whether the logs you're reading predate the last
  restart or deploy.

## Reporting

End every investigation with:

1. **What I found** — the evidence, quoted and bounded.
2. **What I think it means** — the reasoning, with confidence stated.
3. **What I'd suggest** — the proposed fix, as the **exact commands**, clearly
   marked as *not run*, with the environment named and the risk called out
   (especially for uat/prod).
4. **Awaiting your go-ahead** — and then actually wait.
