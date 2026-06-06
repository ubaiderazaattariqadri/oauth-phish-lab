FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx-light \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

COPY . .

RUN rm -f .env
COPY nginx.conf /etc/nginx/sites-enabled/default

EXPOSE 80 443

CMD nginx && gunicorn -w 2 -b 127.0.0.1:5000 server:app
