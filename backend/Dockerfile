FROM node:26-alpine3.23

WORKDIR /app

COPY package*.json .

RUN npm install

COPY server.js .

EXPOSE 5000

CMD [ "node", "server.js" ]
