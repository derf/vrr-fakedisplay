FROM perl:5.30-slim

ARG DEBIAN_FRONTEND=noninteractive

COPY . /app
WORKDIR /app

RUN rm -rf public \
	&& apt-get update \
	&& apt-get -y --no-install-recommends install ca-certificates curl gcc git libc6-dev libdb5.3 libdb5.3-dev libgd3 libgd-dev libssl1.1 libssl-dev libxml2 libxml2-dev make zlib1g-dev \
	&& cpanm -n --no-man-pages --installdeps . \
	&& perl Build.PL \
	&& perl Build \
	&& perl Build manifest \
	&& perl Build install \
	&& rm -rf ~/.cpanm \
	&& apt-get -y purge curl gcc libc6-dev libdb5.3-dev libgd-dev libssl-dev libxml2-dev make zlib1g-dev \
	&& apt-get -y autoremove \
	&& apt-get -y clean \
	&& rm -rf /var/cache/apt/* /var/lib/apt/lists/*

RUN ln -sf ../ext-templates/imprint.html.ep templates/imprint.html.ep \
	&& ln -sf ../ext-templates/privacy.html.ep templates/privacy.html.ep

COPY public /app/public/

EXPOSE 8091

CMD ["hypnotoad", "-f", "index.pl"]
