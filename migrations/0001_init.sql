CREATE TABLE users (
  id          SERIAL PRIMARY KEY,
  public_x    BYTEA NOT NULL UNIQUE,
  public_ed   BYTEA NOT NULL UNIQUE,
  email       TEXT UNIQUE,
  admin_info  JSONB,
  info        JSONB,
  time_reg    TIMESTAMPTZ DEFAULT now(),
  time_upd    TIMESTAMPTZ DEFAULT now()
);

-- для обновления time_upd
CREATE OR REPLACE FUNCTION users_set_time_upd()
RETURNS TRIGGER AS $$
BEGIN
  NEW.time_upd = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- и его триггер
CREATE TRIGGER trg_users_time_upd
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION users_set_time_upd();


CREATE TABLE data (
  id          BIGSERIAL PRIMARY KEY,
  device_id   INT NOT NULL REFERENCES users(id),
  time_send   TIMESTAMPTZ NOT NULL,   -- когда сервер получил
  time        TIMESTAMPTZ NOT NULL,   -- когда данные были измерены
  payload     JSONB NOT NULL
);
CREATE INDEX data_device_time_idx ON data(device_id, time DESC);
-- для поиска внутри телеметрии CREATE INDEX data_payload_gin_idx ON data USING GIN (payload);


-- sudo -u postgres psql
-- DROP DATABASE aguardia;
-- CREATE DATABASE aguardia OWNER aguardia;
-- \c aguardia
-- \dt+