#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

is_port_open() {
  local port="$1"
  (echo >"/dev/tcp/localhost/${port}") >/dev/null 2>&1
}

wait_for_healthy() {
  local container_name="$1"
  local retries=60

  while (( retries > 0 )); do
	local status
	status="$(docker inspect -f '{{.State.Health.Status}}' "${container_name}" 2>/dev/null || true)"
	if [[ "${status}" == "healthy" ]]; then
	  return 0
	fi

	sleep 2
	((retries--))
  done

  echo "Container ${container_name} did not become healthy in time."
  return 1
}

services_to_start=()

if is_port_open 3306; then
  echo "MySQL is reachable at localhost:3306."
else
  echo "MySQL is not reachable at localhost:3306 using MySQLDataSourceProvider settings."
  services_to_start+=("mysql")
fi

if is_port_open 5432; then
  echo "PostgreSQL is reachable at localhost:5432."
else
  echo "PostgreSQL is not reachable at localhost:5432 using PostgreSQLDataSourceProvider settings."
  services_to_start+=("postgres")
fi

if (( ${#services_to_start[@]} > 0 )); then
  echo "Starting Docker services for missing databases: ${services_to_start[*]}"
  docker compose -f "${COMPOSE_FILE}" up -d "${services_to_start[@]}"

  for service in "${services_to_start[@]}"; do
	if [[ "${service}" == "mysql" ]]; then
	  wait_for_healthy hpjp-mysql
	elif [[ "${service}" == "postgres" ]]; then
	  wait_for_healthy hpjp-postgres
	fi
  done
else
  echo "MySQL and PostgreSQL are already reachable. Skipping Docker startup."
fi

pushd "${SCRIPT_DIR}/core" >/dev/null
mvn -DskipTests clean install
popd >/dev/null

pushd "${SCRIPT_DIR}/jooq" >/dev/null
mvn -DskipTests clean install
mvn test-compile
popd >/dev/null
