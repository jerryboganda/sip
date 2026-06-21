# Provider Onboarding — sip.polytronx.com

## 1. Information to collect from the provider (Phase 0)

| Item | Needed value | Goes into |
|------|--------------|-----------|
| Signaling IP(s) | `x.x.x.x/32` (one or more) | `.env` `PROVIDER_SIGNALING_IP(S)`, `pjsip.conf` `match=` |
| RTP / media IP(s) | same or separate | `.env` `PROVIDER_RTP_IPS` (firewall) |
| Gateway / outbound proxy | IP or FQDN | `.env` `PROVIDER_GATEWAY_IP` |
| IP authentication confirmed | they whitelist `185.252.233.186` | — |
| SIP port | usually `5060/UDP` | `.env` `SIP_PORT` |
| CLI / DID handling | provider screens CLI (we pass through, no local config) | provider side |
| Number format | E.164, e.g. `923001234567` or `+923...` | dialplan usage |
| Codecs | `alaw`, `ulaw` (`g729`/`opus`?) | `pjsip.conf` `allow=` |
| DTMF | RFC4733 / RTP events | `pjsip.conf` `dtmf_mode` |
| Max channels / CPS | concurrency + calls-per-second | `asterisk.conf` `maxcalls`, provider side |
| Allowed destinations | PK only / intl / premium blocked | provider side |
| Test number | echo/test destination | testing |
| CDR portal / API | billing + debugging | ops |

> Do not proceed to production calling until the provider IPs are confirmed and
> they have whitelisted our IP. CLI / number screening is done provider-side.

## 2. Onboarding request (send to the provider)

```
Please whitelist our production SIP server for IP authentication:

  Public IP:           185.252.233.186
  FQDN:                sip.polytronx.com
  SIP signaling port:  5060 UDP  (also TCP only if required)
  SIP TLS:             5061 TCP  (only if we use TLS)
  RTP media range:     10000-20000 UDP
  Authentication:      IP authentication / IP ACL (no registration)
  CLI handling:        pass-through (we send the app's CLI unmodified; you screen)
  Preferred codecs:    alaw, ulaw
  DTMF:                RFC4733

Please confirm:
  1. Exact signaling IP(s) we must whitelist.
  2. Exact RTP/media IP(s) we must whitelist.
  3. Exact number format for outbound dialing.
  4. Which header carries CLI (From / P-Asserted-Identity / Remote-Party-ID).
  5. Whether you require SIP OPTIONS qualify.
  6. Whether you rewrite or reject unauthorized CLI.
  7. Whether international/premium routes are disabled by default.
  8. Max concurrent channels, max CPS, and any daily spend cap.
```

## 3. Caller ID rule (pass-through)

Per provider instruction, the PBX applies **no** CLI / number restriction. The
dialplan forwards whatever caller ID, name, number and destination the
application presents, unmodified, in the From + P-Asserted-Identity +
Remote-Party-ID headers. The **provider** performs all CLI screening and
number/destination policy on their side. Ensure your use of caller IDs complies
with applicable regulations and your agreement with the provider.
