FROM debian:bookworm-slim

# nfs-ganesha is a user-space NFS server, no kernel nfsd needed
RUN apt-get update && \
    apt-get install -y --no-install-recommends nfs-ganesha nfs-ganesha-vfs && \
    rm -rf /var/lib/apt/lists/*

COPY ganesha.conf /etc/ganesha/ganesha.conf

RUN mkdir -p /backup_target /run/ganesha

EXPOSE 2049

CMD ["ganesha.nfsd", "-F", "-L", "STDERR", "-f", "/etc/ganesha/ganesha.conf"]
