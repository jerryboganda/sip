# Provider Onboarding — sip.polytronx.com

## 1. Information to collect from the provider (Phase 0)

| Item | Needed value | Goes into |
|------|--------------|-----------|
| Signaling IP(s) | `x.x.x.x/32` (one or more) | `.env` `PROVIDER_SIGNALING_IP(S)`, `pjsip.conf` `match=` |
| RTP / media IP(s) | same or separate | `.env` `PROVIDER_RTP_IPS` (firewall) |
| Gateway / outbound proxy | IP or FQDN | `.env` `PROVIDER_GATEWAY_IP` |
| IP authentication confirmed | they whitelist `185.252.233.186` | — |
| SIP port | usually `5060/UDP` | `.env` `SIP_PORT` |
| Authorized CLI/DID list | exact numbers allowed | `.env` `AUTHORIZED_CLI` |
| Number format | E.164, e.g. `923001234567` or `+923...` | dialplan usage |
| Codecs | `alaw`, `ulaw` (`g729`/`opus`?) | `pjsip.conf` `allow=` |
| DTMF | RFC4733 / RTP events | `pjsip.conf` `dtmf_mode` |
| Max channels / CPS | concurrency + calls-per-second | `asterisk.conf` `maxcalls`, provider side |
| Allowed destinations | PK only / intl / premium blocked | provider side |
| Test number | echo/test destination | testing |
| CDR portal / API | billing + debugging | ops |

> Do not proceed to production calling until provider IPs and the authorized
> CLI list are confirmed.

## 2. Onboarding request (send to the provider)

```
Please whitelist our production SIP server for IP authentication:

  Public IP:           185.252.233.186
  FQDN:                sip.polytronx.com
  SIP signaling port:  5060 UDP  (also TCP only if required)
  SIP TLS:             5061 TCP  (only if we use TLS)
  RTP media range:     10000-20000 UDP
  Authentication:      IP authentication / IP ACL (no registration)
  Allowed outbound CLI: <list only provider-approved numbers>
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

## 3. Caller ID rule (compliance)

Only send CLIs the provider has authorized for this account (your business
number, purchased DID, or verified CLI). Never send numbers you do not control
(banks, government, third parties). The dialplan `[outbound]` context already
forces `AUTHORIZED_CLI` on every call so an app cannot present anything else.
