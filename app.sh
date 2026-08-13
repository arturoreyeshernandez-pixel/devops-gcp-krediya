#!/bin/sh

PORT=${PORT:-8080}
echo "Servidor iniciado en el puerto $PORT..."

while true; do
  echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"message\": \"Hello World desde Bash en AWS!\", \"status\": \"OK\"}" | nc -l -p $PORT -q 1
done