FROM alpine:latest

RUN apk add --no-cache curl tzdata

WORKDIR /app
COPY update.sh /app/update.sh
COPY lib/ /app/lib/
RUN chmod 644 /app/update.sh /app/lib/*.sh && chmod 755 /app /app/lib

CMD ["sh", "/app/update.sh"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD sh /app/update.sh --healthcheck
