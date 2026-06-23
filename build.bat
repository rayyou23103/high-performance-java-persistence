@echo off
setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "COMPOSE_FILE=%SCRIPT_DIR%docker-compose.yml"

pushd "%SCRIPT_DIR%"

call :check_port 3306
if errorlevel 1 (
	set "MYSQL_AVAILABLE=0"
	echo MySQL is not reachable at localhost:3306 using MySQLDataSourceProvider settings.
) else (
	set "MYSQL_AVAILABLE=1"
	echo MySQL is reachable at localhost:3306.
)

call :check_port 5432
if errorlevel 1 (
	set "POSTGRES_AVAILABLE=0"
	echo PostgreSQL is not reachable at localhost:5432 using PostgreSQLDataSourceProvider settings.
) else (
	set "POSTGRES_AVAILABLE=1"
	echo PostgreSQL is reachable at localhost:5432.
)

set "SERVICES_TO_START="
if "!MYSQL_AVAILABLE!"=="0" set "SERVICES_TO_START=!SERVICES_TO_START! mysql"
if "!POSTGRES_AVAILABLE!"=="0" set "SERVICES_TO_START=!SERVICES_TO_START! postgres"

if defined SERVICES_TO_START (
	echo Starting Docker services for missing databases:!SERVICES_TO_START!
	call docker compose -f "%COMPOSE_FILE%" up -d!SERVICES_TO_START!
	if errorlevel 1 (
		echo Failed to start Docker services. Ensure Docker Desktop is running.
		popd
		exit /b 1
	)

	if "!MYSQL_AVAILABLE!"=="0" (
		call :wait_for_healthy hpjp-mysql
		if errorlevel 1 (
			popd
			exit /b 1
		)
	)

	if "!POSTGRES_AVAILABLE!"=="0" (
		call :wait_for_healthy hpjp-postgres
		if errorlevel 1 (
			popd
			exit /b 1
		)
	)
) else (
	echo MySQL and PostgreSQL are already reachable. Skipping Docker startup.
)

pushd core
call mvn -DskipTests clean install
if errorlevel 1 (
	popd
	popd
	exit /b 1
)
popd

pushd jooq
call mvn -DskipTests clean install
if errorlevel 1 (
	popd
	popd
	exit /b 1
)

call mvn test-compile
if errorlevel 1 (
	popd
	popd
	exit /b 1
)
popd

popd
goto:eof

:check_port
powershell -NoProfile -Command "$client = New-Object Net.Sockets.TcpClient; try { $iar = $client.BeginConnect('localhost', %~1, $null, $null); if (-not $iar.AsyncWaitHandle.WaitOne(1000)) { exit 1 }; $client.EndConnect($iar) | Out-Null; exit 0 } catch { exit 1 } finally { $client.Close() }"
exit /b %ERRORLEVEL%

:wait_for_healthy
set "CONTAINER_NAME=%~1"
set /a RETRIES=60

:healthcheck_loop
set "STATUS="
for /f %%i in ('docker inspect -f "{{.State.Health.Status}}" %CONTAINER_NAME% 2^>nul') do set "STATUS=%%i"

if /I "%STATUS%"=="healthy" goto:eof

set /a RETRIES-=1
if %RETRIES% LEQ 0 (
	echo Container %CONTAINER_NAME% did not become healthy in time.
	exit /b 1
)

timeout /t 2 /nobreak >nul
goto healthcheck_loop

