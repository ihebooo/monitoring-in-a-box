# monitoring-in-a-box

[![CI](https://github.com/ihebooo/monitoring-in-a-box/actions/workflows/ci.yml/badge.svg)](https://github.com/ihebooo/monitoring-in-a-box/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Prometheus + node_exporter + postgres_exporter + Grafana in one Docker Compose file — a
small, pinned, tested monitoring stack for Linux and PostgreSQL servers.**

CI starts the whole stack on every push and fails unless every Prometheus target is `up`,
postgres_exporter reaches PostgreSQL, the alert rules load, and Grafana can query Prometheus
through its provisioned datasource. The alert rules also have `promtool` unit tests.

> Work in progress. Coming next: blackbox_exporter (HTTPS + certificate expiry), Alertmanager
> and ready-made Grafana dashboards.

## Quick start

```bash
git clone https://github.com/ihebooo/monitoring-in-a-box.git
cd monitoring-in-a-box
cp .env.example .env            # set GRAFANA_ADMIN_PASSWORD
docker compose up -d
./scripts/check_targets.sh      # waits until every target is up
```

| Service | URL | Notes |
|---|---|---|
| Prometheus | http://localhost:9090 | targets: *Status → Targets* |
| Grafana | http://localhost:3000 | login from `.env`; Prometheus datasource is pre-provisioned |
| node_exporter | not published | scraped by Prometheus over the Compose network |
| postgres_exporter | not published | job `postgres`, watches the demo PostgreSQL |
| PostgreSQL (demo) | not published | only there so the alerts have something to watch |

Ports are published on **127.0.0.1 only**. To reach them from other machines, put a reverse
proxy with TLS in front, or set `BIND_ADDR=0.0.0.0` in `.env` on a trusted network.

## What's inside

| Path | Purpose |
|---|---|
| [`docker-compose.yml`](docker-compose.yml) | the three services, pinned image versions, named volumes |
| [`prometheus/prometheus.yml`](prometheus/prometheus.yml) | scrape jobs: `prometheus`, `node` (the Docker host), `grafana`, `postgres` |
| [`prometheus/rules/postgresql.yml`](prometheus/rules/postgresql.yml) | PostgreSQL alert rules (see below) |
| [`prometheus/tests/`](prometheus/tests/) | `promtool test rules` unit tests for every alert |
| [`postgres/initdb/`](postgres/initdb/) | creates the read-only `postgres_exporter` login (`pg_monitor`) |
| [`grafana/provisioning/`](grafana/provisioning/) | Prometheus datasource (uid `prometheus`, default) |
| [`scripts/check_targets.sh`](scripts/check_targets.sh) | waits for all targets to be `up`; monitoring-style exit codes |
| [`.env.example`](.env.example) | Grafana / PostgreSQL passwords, bind address, retention |

## `check_targets.sh`

```text
$ ./scripts/check_targets.sh --min 3
JOB              INSTANCE                     HEALTH   LAST_ERROR
grafana          grafana:3000                 up
node             docker-host                  up
prometheus       localhost:9090               up

OK: all 3 targets up
```

| Exit code | Meaning |
|---|---|
| 0 | all active targets up (and at least `--min`) |
| 1 | some targets still down when `--timeout` ran out |
| 2 | Prometheus not reachable, or `curl` / `jq` missing |
| 3 | usage error |

Options: `-u URL`, `-t TIMEOUT`, `-i INTERVAL`, `-m MIN`, `-h`, `-V`. Useful after
`docker compose up`, after editing `prometheus.yml`, or as a cron/CI check.

## PostgreSQL alerts

| Alert | Expression (simplified) | For | Severity |
|---|---|---|---|
| `PostgreSQLDown` | `pg_up == 0` — exporter runs but cannot connect | 1m | critical |
| `PostgresExporterDown` | `up{job="postgres"} == 0` — no data at all | 1m | warning |
| `PostgreSQLReplicationLag` | `pg_replication_lag_seconds > 30` on a standby only | 5m | warning |
| `PostgreSQLTooManyConnections` | backends / `max_connections` > 80 % | 5m | warning |

See them in Prometheus under *Alerts*. Alertmanager (notifications) comes in a later step.
Test the rules after editing them:

```bash
docker run --rm --entrypoint promtool -w /etc/prometheus/tests   -v "$PWD/prometheus:/etc/prometheus:ro" prom/prometheus:v2.55.1 test rules postgresql_test.yml
```

### Monitor your own PostgreSQL

1. Create the monitoring login on that server (PostgreSQL 10+):

   ```sql
   CREATE ROLE postgres_exporter LOGIN PASSWORD '...' CONNECTION LIMIT 3;
   GRANT pg_monitor TO postgres_exporter;
   ```

   and allow it in `pg_hba.conf` from the monitoring host only.
2. In `docker-compose.yml`, set `DATA_SOURCE_URI` of `postgres-exporter` to
   `db1.example.com:5432/postgres?sslmode=require`, and remove the demo `postgres` service.
3. Change `instance: demo-postgres` in `prometheus/prometheus.yml` to the server name.
   For several servers, run one exporter per server.

## Monitor more Linux servers

1. Install node_exporter on the server (package `prometheus-node-exporter` on Debian/Ubuntu,
   or the [release binary](https://github.com/prometheus/node_exporter/releases) + a systemd unit).
2. Allow TCP 9100 from the monitoring host only.
3. Add the server to `prometheus/prometheus.yml`:

   ```yaml
   - job_name: node-remote
     static_configs:
       - targets: ["db1.example.com:9100"]
   ```

4. Reload without a restart: `curl -X POST http://localhost:9090/-/reload`, then run
   `./scripts/check_targets.sh`.

## Notes

- node_exporter runs with `pid: host` and the host's `/` mounted read-only at `/host`, so CPU,
  memory, disk and filesystem metrics are the host's. Network metrics are from the container's
  network namespace; use `network_mode: host` if you need the host interfaces.
- Data lives in the named volumes `prometheus-data`, `grafana-data` and `postgres-data`;
  `docker compose down -v` deletes it. The PostgreSQL passwords in `.env` only apply when
  `postgres-data` is created the first time.
- Prometheus retention defaults to 15 days (`PROMETHEUS_RETENTION`).

## Related

- [pg-health-report](https://github.com/ihebooo/pg-health-report) — one-script PostgreSQL health report
- [linux-db-tuning-check](https://github.com/ihebooo/linux-db-tuning-check) — Linux kernel/OS settings check for database hosts
- [linux-ops-runbooks](https://github.com/ihebooo/linux-ops-runbooks) — runbooks and scripts behind these tools

## License

[MIT](LICENSE)
