FROM nginx:alpine

# Copy custom nginx configuration with autoindex enabled
COPY default.conf /etc/nginx/conf.d/default.conf

RUN rm -f /usr/share/nginx/html/index.html /usr/share/nginx/html/50x.html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]