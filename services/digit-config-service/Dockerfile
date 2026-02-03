FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY tsconfig.json ./
COPY src ./src

# For production, build and run
# RUN npm run build
# CMD ["npm", "start"]

# For development with hot reload
CMD ["npm", "run", "dev"]
