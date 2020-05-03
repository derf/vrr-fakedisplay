# docker build -t vrr-fakedisplay:latest --build-arg=vrrf_version=$(git describe --dirty) .

FROM debian:buster-slim AS files

ARG vrrf_version=git

COPY Build.PL cpanfile index.pl /app/
COPY lib/ /app/lib/
COPY public/ /app/public/
COPY share/ /app/share/
COPY templates/ /app/templates/

WORKDIR /app

RUN ln -sf ../ext-templates/imprint.html.ep templates/imprint.html.ep \
	&& ln -sf ../ext-templates/privacy.html.ep templates/privacy.html.ep

RUN find lib -name '*.pm' -or -name '*.PL' | xargs sed -i \
	-e "s/VERSION *= *.*;/VERSION = '${vrrf_version}';/"

RUN sed -i -e "s/VERSION *= *.*;/VERSION = '${vrrf_version}';/" \
	index.pl


FROM perl:5.30-slim

ARG DEBIAN_FRONTEND=noninteractive
ARG APT_LISTCHANGES_FRONTEND=none

COPY --from=files /app/ /app/

WORKDIR /app

RUN apt-get update \
	&& apt-get -y --no-install-recommends install \
		ca-certificates \
		curl \
		gcc \
		libc6-dev \
		libdb5.3 \
		libdb5.3-dev \
		libgd3 \
		libgd-dev \
		libssl1.1 \
		libssl-dev \
		libxml2 \
		libxml2-dev \
		make \
		zlib1g-dev \
	&& cpanm -n --no-man-pages --installdeps . \
	&& mv public / \
	&& perl Build.PL \
	&& perl Build \
	&& perl Build manifest \
	&& perl Build install \
	&& rm -rf ~/.cpanm _build blib MANIFEST* META* MYMETA* \
	&& mv /public . \
	&& apt-get -y purge \
		curl \
		gcc \
		libc6-dev \
		libdb5.3-dev -\
		libgd-dev \
		libssl-dev \
		libxml2-dev \
		make \
		zlib1g-dev \
	&& apt-get -y autoremove \
	&& rm -rf /var/cache/apt/* /var/lib/apt/lists/*

EXPOSE 8091

CMD ["hypnotoad", "-f", "index.pl"]
