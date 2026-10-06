#!/usr/bin/env python3
"""A stand-in for prefill-host and the Mac app, for end-to-end runs of the Chrome extension
on machines without the Mac app. It speaks Chrome's native messaging framing (a 4-byte
length, then JSON) and answers with the Alex Rivera test card. Every request is logged to
the file named by PREFILL_FAKE_LOG, so a test can check what the extension asked."""
import json
import os
import struct
import sys

CARD = {
    "emails": ["alex.rivera@example.com", "alex@work.example.org"],
    "phones": ["+1 (510) 555-0134"],
    "addresses": [{"street": "2400 Durant Ave", "city": "Berkeley", "state": "CA", "postalCode": "94704", "country": "United States"}],
    "name": {"given": "Alex", "family": "Rivera"},
}
LINKS = [
    {"type": "github", "url": "https://github.com/alexrivera"},
    {"type": "linkedin", "url": "https://www.linkedin.com/in/alexrivera"},
    {"type": "website", "url": "https://alexrivera.dev"},
]
# Picks outlive one run of the host, as Chrome starts it for each message.
STATE = os.environ.get("PREFILL_FAKE_STATE")


def pinned_email():
    if not STATE or not os.path.exists(STATE):
        return None
    with open(STATE) as handle:
        return json.load(handle).get("email")


def ranked_emails():
    pin = pinned_email()
    return sorted(CARD["emails"], key=lambda email: email != pin)


CUSTOM = [("school", "University of California, Berkeley"), ("authorized", "Yes"), ("sponsorship", "No"), ("hear", "LinkedIn")]


def answer(request):
    kind = request.get("type")
    if kind == "ping":
        return {"type": "pong"}
    if kind == "contactSuggestions":
        if request.get("offCard"):
            return {"type": "contactSuggestionsResult", "emails": [], "phones": [], "addresses": []}
        kinds = {field["kind"] for field in request.get("fields", [])}
        return {
            "type": "contactSuggestionsResult",
            "emails": ranked_emails() if "email" in kinds else [],
            "phones": CARD["phones"] if "phone" in kinds else [],
            "addresses": CARD["addresses"] if "address" in kinds else [],
            **({"name": CARD["name"]} if "name" in kinds else {}),
        }
    if kind == "linkSuggestions":
        return {"type": "linkSuggestionsResult", "links": [link for link in LINKS if link["type"] in request.get("types", [])]}
    if kind == "customSuggestions":
        fields = [{"values": [value for word, value in CUSTOM if word in field["text"].lower()][:1]} for field in request.get("fields", [])]
        return {"type": "customSuggestionsResult", "fields": fields}
    if kind == "picked":
        remembered = request.get("kind") == "email" and request.get("value") in CARD["emails"] and STATE is not None
        if remembered:
            with open(STATE, "w") as handle:
                json.dump({"email": request["value"]}, handle)
        return {"type": "pickedResult", "remembered": remembered}
    if kind == "capture":
        return {"type": "captureResult", "saved": 0, "review": 0, "ignored": 0}
    if kind == "pageContext":
        return {"type": "pageContextResult", "status": "unchanged"}
    return {"type": "error", "reason": "unknown request"}


def main():
    log = os.environ.get("PREFILL_FAKE_LOG")
    while True:
        header = sys.stdin.buffer.read(4)
        if len(header) < 4:
            return
        request = json.loads(sys.stdin.buffer.read(struct.unpack("<I", header)[0]))
        if log:
            with open(log, "a") as handle:
                handle.write(json.dumps(request) + "\n")
        body = json.dumps(answer(request)).encode()
        sys.stdout.buffer.write(struct.pack("<I", len(body)) + body)
        sys.stdout.buffer.flush()


main()
