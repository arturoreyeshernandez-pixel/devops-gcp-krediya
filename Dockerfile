FROM alpine:latest

RUN apk add --no-cache netcat-openbsd

WORKDIR /app
COPY app.sh .

RUN chmod +x app.sh

EXPOSE 8080

CMD ["./app.sh"]