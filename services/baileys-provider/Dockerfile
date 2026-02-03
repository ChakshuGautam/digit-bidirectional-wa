FROM node:20-alpine

WORKDIR /app

# Install dependencies for Baileys
RUN apk add --no-cache python3 make g++ git

COPY package*.json ./
RUN npm install

COPY tsconfig.json ./
COPY src ./src

# Session data persisted via volume
RUN mkdir -p /app/auth_info

# For development with hot reload
CMD ["npm", "run", "dev"]
