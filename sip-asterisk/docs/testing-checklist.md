# Testing Checklist — sip.polytronx.com

Run `bash scripts/06-testing-checklist.sh` for the automated parts, then work
through the manual steps below.

## Network

```bash
dig +short sip.polytronx.com A                       # -> 185.252.233.186
ss -tulpn | grep -E ':5060|:5061|:10000|:20000'      # SIP/RTP listening
docker logs --tail=100 sip-asterisk
```

## SIP trace

```bash
docker exec -it sip-asterisk sngrep
# or:
docker exec -it sip-asterisk asterisk -rx "pjsip set logger on"   # ... then off
tcpdump -ni any port 5060
tcpdump -ni any udp portrange 10000-20000
```

## Asterisk state

```bash
docker exec -it sip-asterisk asterisk -rx "pjsip show endpoint provider-endpoint"
docker exec -it sip-asterisk asterisk -rx "pjsip show contacts"
docker exec -it sip-asterisk asterisk -rx "pjsip show aors"
docker exec -it sip-asterisk asterisk -rx "core show channels"
```

## Call tests (in order)

1. Provider SIP OPTIONS / qualify responds (AOR shows `Avail`).
2. Outbound call to the provider test/echo number.
3. Outbound call to your own mobile.
4. Verify **two-way audio**.
5. Verify the displayed **CLI == AUTHORIZED_CLI**.
6. Check the provider CDR + local `./logs/cdr-csv/Master.csv`.
7. Check Asterisk logs for warnings/errors.
8. Negative test: attempt an unauthorized CLI → provider must reject/override.
9. Test max-duration limit.
10. Test blocked destinations.

## Failure reference

| Symptom | Likely cause |
|---------|--------------|
| `403 Forbidden` | IP not whitelisted or CLI not authorized |
| `401 Unauthorized` | Provider expects registration auth, not IP-auth |
| `404` / `484` | Wrong dialed-number format |
| Call connects, no audio | RTP firewall / NAT issue |
| One-way audio | RTP source IP/range mismatch (`external_media_address`, RTP IPs) |
| `488 Not Acceptable Here` | Codec mismatch (`allow=alaw,ulaw`) |
| Wrong CLI displayed | Provider overriding CLI or wrong header format |
| Random SIP scans | Firewall too open |
