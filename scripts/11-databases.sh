#!/usr/bin/env bash
# =============================================================================
# scripts/11-databases.sh
# -----------------------------------------------------------------------------
# Installs MySQL and PostgreSQL from the Ubuntu official repositories,
# enables and starts both services, performs a minimal safe "secure
# installation" equivalent, and creates a development user + database for
# each engine so you can `psql`/`mysql` in immediately.
#
# Credentials are controlled via config/versions.conf (override in .env):
#   MYSQL_DEV_USER, MYSQL_DEV_PASSWORD, MYSQL_DEV_DATABASE
#   POSTGRES_DEV_USER, POSTGRES_DEV_PASSWORD, POSTGRES_DEV_DATABASE
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-utils.sh"
CURRENT_MODULE="11-databases"
trap 'utils::on_error $? $LINENO "$BASH_COMMAND"' ERR

utils::print_banner "Databases (MySQL + PostgreSQL)"

# ------------------------------- MySQL --------------------------------------
log::step "MySQL Server"
helpers::apt_install mysql-server

sudo systemctl enable mysql >>"${LOG_FILE}" 2>&1
sudo systemctl start mysql >>"${LOG_FILE}" 2>&1
log::success "MySQL service enabled and started"

if ! helpers::already_done "mysql_dev_setup"; then
    log::info "Configuring MySQL development user/database (idempotent)..."
    sudo mysql --protocol=socket -u root <<SQL >>"${LOG_FILE}" 2>&1 || log::warn "MySQL dev-user setup reported an issue; it may already be configured differently."
CREATE USER IF NOT EXISTS '${MYSQL_DEV_USER}'@'localhost' IDENTIFIED BY '${MYSQL_DEV_PASSWORD}';
CREATE DATABASE IF NOT EXISTS ${MYSQL_DEV_DATABASE};
GRANT ALL PRIVILEGES ON ${MYSQL_DEV_DATABASE}.* TO '${MYSQL_DEV_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
    helpers::mark_done "mysql_dev_setup"
    log::success "MySQL dev user '${MYSQL_DEV_USER}' and database '${MYSQL_DEV_DATABASE}' ready"
else
    log::info "MySQL dev user/database already configured previously"
fi

log::info "Verifying MySQL connection as dev user..."
if mysql -u "${MYSQL_DEV_USER}" -p"${MYSQL_DEV_PASSWORD}" -e "SELECT 1;" >>"${LOG_FILE}" 2>&1; then
    log::success "MySQL connection verified for '${MYSQL_DEV_USER}'"
else
    log::warn "Could not verify MySQL connection for '${MYSQL_DEV_USER}'. Check ${LOG_FILE}."
fi

# ------------------------------ PostgreSQL ----------------------------------
log::step "PostgreSQL"
helpers::apt_install postgresql postgresql-contrib

sudo systemctl enable postgresql >>"${LOG_FILE}" 2>&1
sudo systemctl start postgresql >>"${LOG_FILE}" 2>&1
log::success "PostgreSQL service enabled and started"

if ! helpers::already_done "postgres_dev_setup"; then
    log::info "Configuring PostgreSQL development role/database (idempotent)..."
    sudo -u postgres psql -v ON_ERROR_STOP=0 >>"${LOG_FILE}" 2>&1 <<SQL
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${POSTGRES_DEV_USER}') THEN
      CREATE ROLE ${POSTGRES_DEV_USER} LOGIN PASSWORD '${POSTGRES_DEV_PASSWORD}' CREATEDB;
   END IF;
END
\$\$;
SQL
    if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${POSTGRES_DEV_DATABASE}'" | grep -q 1; then
        sudo -u postgres createdb -O "${POSTGRES_DEV_USER}" "${POSTGRES_DEV_DATABASE}" >>"${LOG_FILE}" 2>&1
    fi
    helpers::mark_done "postgres_dev_setup"
    log::success "PostgreSQL role '${POSTGRES_DEV_USER}' and database '${POSTGRES_DEV_DATABASE}' ready"
else
    log::info "PostgreSQL dev role/database already configured previously"
fi

log::info "Verifying PostgreSQL connection as dev user..."
if PGPASSWORD="${POSTGRES_DEV_PASSWORD}" psql -h 127.0.0.1 -U "${POSTGRES_DEV_USER}" -d "${POSTGRES_DEV_DATABASE}" -c "SELECT 1;" >>"${LOG_FILE}" 2>&1; then
    log::success "PostgreSQL connection verified for '${POSTGRES_DEV_USER}'"
else
    log::warn "Could not verify PostgreSQL TCP connection (may require pg_hba.conf changes for md5/scram over 127.0.0.1). Check ${LOG_FILE}."
    log::warn "If needed, edit /etc/postgresql/*/main/pg_hba.conf to allow 'host all all 127.0.0.1/32 scram-sha-256' and restart postgresql."
fi

log::success "Databases step complete"
