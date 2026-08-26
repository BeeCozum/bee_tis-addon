#!/usr/bin/env bash
set -e

# Create data directory if it doesn't exist
mkdir -p /data

# Debugging: Output environment variables
echo "Environment variables:"
echo "INGRESS_URL: $INGRESS_URL"
echo "SUPERVISOR_TOKEN: ${SUPERVISOR_TOKEN:0:5}..." # Only show first few chars for security
echo "HOSTNAME: $HOSTNAME"

# Generate the proper APP_URL based on Home Assistant Ingress
if [ -n "$INGRESS_URL" ]; then
    echo "Setting up for ingress at $INGRESS_URL"
    INGRESS_FULL_URL="$INGRESS_URL"
elif [ -n "$HTTP_X_INGRESS_PATH" ] && [ -n "$HTTP_HOST" ]; then
    # Fallback: Build INGRESS_URL from HTTP_X_INGRESS_PATH and HTTP_HOST
    echo "INGRESS_URL not provided, building from HTTP_X_INGRESS_PATH"
    INGRESS_FULL_URL="http://${HTTP_HOST}${HTTP_X_INGRESS_PATH}"
    echo "Constructed INGRESS_URL: $INGRESS_FULL_URL"
else
    INGRESS_FULL_URL=""
    echo "No ingress info available, using default settings"
fi

if [ -n "$INGRESS_FULL_URL" ]; then
    # Update the .env file with the ingress URL
    sed -i "s#APP_URL=.*#APP_URL=${INGRESS_FULL_URL}#g" /laravel/.env

    # Add ingress path to .env for dynamic handling
    INGRESS_PATH_ONLY=$(echo $INGRESS_FULL_URL | sed 's/^.*\/\/[^/]*//')
    # Remove old INGRESS_PATH line if exists
    sed -i "/^INGRESS_PATH=/d" /laravel/.env
    echo "INGRESS_PATH=${INGRESS_PATH_ONLY}" >> /laravel/.env

    # Extract protocol from INGRESS_FULL_URL to set secure cookies if needed
    if [[ "$INGRESS_FULL_URL" == https://* ]]; then
        echo "HTTPS detected, enabling secure cookies"
        sed -i "s#SESSION_SECURE_COOKIE=.*#SESSION_SECURE_COOKIE=true#g" /laravel/.env
    else
        echo "HTTP detected, disabling secure cookies"
        sed -i "s#SESSION_SECURE_COOKIE=.*#SESSION_SECURE_COOKIE=false#g" /laravel/.env
    fi
fi

# Check if database exists, create if not
if [ ! -f /data/database.sqlite ]; then
    touch /data/database.sqlite
    # Set proper permissions
    chmod 777 /data/database.sqlite
fi

# Create symbolic link to the persistent database
ln -sf /data/database.sqlite /laravel/database.sqlite

# Run migrations if database is new or on first run
if [ ! -f /data/db_initialized ]; then
    php /laravel/artisan migrate --force
    php /laravel/artisan db:seed --force
    touch /data/db_initialized
fi

# Clear all caches to ensure new settings are applied
php /laravel/artisan optimize
php /laravel/artisan config:clear
php /laravel/artisan route:clear
php /laravel/artisan view:clear
php /laravel/artisan cache:clear

echo "Waiting for system to stabilize..."
sleep 2  # Add a small delay to ensure everything is ready

# Start Laravel server with longer timeout
exec php /laravel/artisan serve --host=0.0.0.0 --port=8000
