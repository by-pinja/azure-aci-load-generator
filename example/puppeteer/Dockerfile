FROM alpine:3.10.2

RUN apk add --no-cache \
      chromium \
      nss \
      freetype \
      freetype-dev \
      harfbuzz \
      ca-certificates \
      ttf-freefont \
      nodejs \
      npm

# Tell Puppeteer to skip installing Chrome. We'll be using the installed package.
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD true

ENV CHROME_PATH=/usr/bin/chromium-browser
ENV CHROME_HEADLESS=1

COPY ./ /src/

WORKDIR /src/

RUN npm install && chmod +x ./entry.sh

ENTRYPOINT [ "./entry.sh" ]
