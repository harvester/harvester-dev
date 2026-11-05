FROM nginx:alpine

RUN apk add --no-cache ca-certificates

# The entrypoint renders templates into /etc/nginx/conf.d/ with envsubst.
# NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1 exports NGINX_LOCAL_RESOLVERS from
# /etc/resolv.conf so the proxy locations can resolve hostnames.
ENV NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1
COPY default.conf /etc/nginx/templates/default.conf.template

# Proxy locations, linked into /etc/nginx/server.d/ at startup only when
# ARTIFACTS_PROXY_ENABLED=true.
COPY proxy.conf /etc/nginx/artifacts/proxy.conf
COPY 40-artifacts-proxy.sh /docker-entrypoint.d/40-artifacts-proxy.sh

RUN rm -f /etc/nginx/conf.d/default.conf \
    /usr/share/nginx/html/index.html /usr/share/nginx/html/50x.html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
