"""PostgreSQL-Zugriff und Tabellen des Guthaben-Dienstes."""
from __future__ import annotations

import logging
import os
import time

import psycopg
from psycopg.rows import dict_row

log = logging.getLogger("tuut.db")

SCHEMA = """
CREATE TABLE IF NOT EXISTS accounts (
  user_id        TEXT PRIMARY KEY,
  balance_cents  BIGINT NOT NULL DEFAULT 0,
  reserved_cents BIGINT NOT NULL DEFAULT 0 CHECK (reserved_cents >= 0),
  blocked        BOOLEAN NOT NULL DEFAULT FALSE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Jede Guthabenbewegung genau einmal (UNIQUE kind+reference verhindert Doppelbuchungen).
CREATE TABLE IF NOT EXISTS ledger (
  id                  BIGSERIAL PRIMARY KEY,
  user_id             TEXT NOT NULL REFERENCES accounts(user_id),
  kind                TEXT NOT NULL,            -- topup | call | korrektur
  reference           TEXT NOT NULL,            -- Stripe-Session-ID bzw. Gesprächs-ID
  amount_cents        BIGINT NOT NULL,          -- + Gutschrift, - Belastung
  balance_after_cents BIGINT NOT NULL,
  text                TEXT NOT NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (kind, reference)
);
CREATE INDEX IF NOT EXISTS ledger_user ON ledger(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS topups (
  session_id   TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL,
  amount_cents BIGINT NOT NULL CHECK (amount_cents > 0),
  status       TEXT NOT NULL DEFAULT 'open',    -- open | paid | expired | pruefen
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  credited_at  TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS pstn_calls (
  id                TEXT PRIMARY KEY,
  user_id           TEXT NOT NULL REFERENCES accounts(user_id),
  number            TEXT NOT NULL,
  destination       TEXT NOT NULL,
  rate_hc           BIGINT NOT NULL,
  fee_cents         BIGINT NOT NULL,
  takt_first        INT NOT NULL,
  takt_next         INT NOT NULL,
  reserved_cents    BIGINT NOT NULL,
  max_seconds       INT NOT NULL,
  status            TEXT NOT NULL,              -- reserved | connected | ended
  provider          TEXT NOT NULL,
  provider_call_id  TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  connected_at      TIMESTAMPTZ,
  last_heartbeat_at TIMESTAMPTZ,
  ended_at          TIMESTAMPTZ,
  billed_seconds    INT,
  cost_cents        BIGINT
);
CREATE INDEX IF NOT EXISTS pstn_calls_user ON pstn_calls(user_id, created_at DESC);

-- Abgleich mit den Abrechnungsdaten des Telefonie-Anbieters.
CREATE TABLE IF NOT EXISTS provider_cdrs (
  provider         TEXT NOT NULL,
  provider_call_id TEXT NOT NULL,
  call_id          TEXT,
  seconds          INT NOT NULL,
  received_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  abweichung       TEXT,
  PRIMARY KEY (provider, provider_call_id)
);
"""


def dsn() -> str:
    return os.environ["DATABASE_URL"]


def connect() -> psycopg.Connection:
    return psycopg.connect(dsn(), row_factory=dict_row)


def init_schema(retries: int = 30) -> None:
    for attempt in range(1, retries + 1):
        try:
            with connect() as conn:
                conn.execute(SCHEMA)
            log.info("Datenbank bereit")
            return
        except psycopg.OperationalError as e:
            log.warning("Datenbank noch nicht bereit (%s/%s): %s", attempt, retries, e)
            time.sleep(2)
    raise RuntimeError("Datenbank nicht erreichbar")


def ensure_account(conn: psycopg.Connection, user_id: str) -> None:
    conn.execute("INSERT INTO accounts (user_id) VALUES (%s) ON CONFLICT DO NOTHING", (user_id,))
