# Коментар для LMS — ДЗ 6

Для наскрізного розбору обрав **ithillel.ua**: DNS-зона обслуговується
Cloudflare, а сайт розміщений у Hetzner. Роботу виконав на macOS, тому
замість `ip route get` використав `route -n get`; дамп зняв через `tshark`
і проаналізував у Wireshark.

## Основні результати

| Перевірка | Результат |
|---|---|
| DNS | A `78.47.64.83`, AAAA `2a01:4f8:c012:dc97::1`, NS Cloudflare |
| Route | IPv4 через `10.20.50.1`/`en0`; локального IPv6-маршруту немає |
| Traceroute | 12 хопів ICMP, кінцевий RTT близько 40–45 мс |
| TCP/TLS | handshake — кадри 1–3; ClientHello з SNI — кадр 4; ServerHello — кадр 8 |
| `curl -w` | DNS 6 мс; TCP +38 мс; TLS +43 мс; TTFB +44 мс; тіло +210 мс |
| Сертифікат | Let's Encrypt YR2, 72 дні до завершення, `Verification: OK` |

У ClientHello ім'я `ithillel.ua` видно у SNI відкритим текстом. ServerHello
обирає TLS 1.3 і `TLS_AES_256_GCM_SHA384`; перші HTTP-дані з'являються
близько 0.12 с, а `curl -v` розшифровує відповідь як `HTTP/2 200` від nginx.
Із фаз встановлення найдовший TLS-handshake (~43 мс), але загалом найбільше
часу займає завантаження HTML-тіла (~210 мс).

`openssl s_client -showcerts` показав leaf-сертифікат та потрібні проміжні
сертифікати; кореневий береться зі сховища довіри клієнта. Сертифікат діє
до 05.10.2026.

## Опціональна частина

- **SSL Labs:** A+ для IPv4 та IPv6, TLS 1.2/1.3, forward secrecy і HSTS.
- **Що поліпшити:** прибрати чотири CBC-набори TLS 1.2, позначені weak.
- **Mozilla Intermediate:** сайт близький до профілю, але відрізняються
  TLS 1.2 cipher list і HSTS `max-age` (1 рік проти рекомендованих 2).
- **Власний сервіс:** сучасні ciphers, HSTS, моніторинг строку сертифіката,
  коректний ICMP для PMTUD та WireGuard-доступ без прямого port forwarding.

**Повний звіт зі скріншотами:**
https://github.com/apongmail/domashka/blob/main/domashka-06/report_domashka-06.md

**PDF:**
https://github.com/apongmail/domashka/blob/main/domashka-06/report_domashka-06.pdf

PCAP і вихідні дані команд лежать у `domashka-06/docs/`.