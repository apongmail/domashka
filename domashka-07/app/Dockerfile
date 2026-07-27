FROM python:3.12-slim

WORKDIR /app

# Залежності копіюються окремо від коду: поки requirements.txt не змінився,
# шар з pip install береться з кешу і зміна коду не тягне переустановку.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8000

CMD ["python", "app.py"]
