FROM node:20-alpine as front-build

COPY ./front /src

WORKDIR /src

RUN npm ci \
    && npx @angular/cli build --optimization

FROM gradle:8.7-jdk17 as back-build

COPY ./back /src

WORKDIR /src

RUN gradle build

FROM caddy:2-alpine as front

COPY --from=front-build /src/dist/microcrm/browser /app/front
# Copie dans l'emplacement par défaut de l'image officielle caddy:2-alpine
COPY misc/docker/Caddyfile /etc/caddy/Caddyfile

EXPOSE 80
# CMD par défaut de l'image : caddy run --config /etc/caddy/Caddyfile --adapter caddyfile

FROM eclipse-temurin:17-jre-alpine as back

COPY --from=back-build /src/build/libs/microcrm-0.0.1-SNAPSHOT.jar /app/microcrm-0.0.1-SNAPSHOT.jar

WORKDIR /app

EXPOSE 8080

CMD ["java", "-jar", "/app/microcrm-0.0.1-SNAPSHOT.jar"]

FROM alpine:3.20 as standalone

COPY --from=front / /
COPY --from=back / /
COPY misc/docker/supervisor.ini /app/supervisor.ini

RUN apk add supervisor

WORKDIR /app

CMD ["/usr/bin/supervisord", "-c", "/app/supervisor.ini"]



