# Triage Labels

**Label source:** GitHub Issues labels on marscey/coriander_player

## Label vocabulary

| Role | Label | Meaning |
|------|-------|---------|
| Needs triage | `needs-triage` | Maintainer needs to evaluate |
| Needs info | `needs-info` | Waiting on reporter to provide more details |
| Ready for agent | `ready-for-agent` | Fully specified, an AFK agent can pick it up |
| Ready for human | `ready-for-human` | Needs human implementation |
| Won't fix | `wontfix` | Will not be actioned |

## State machine

```
[New issue] → needs-triage
needs-triage → needs-info (reporter needs to clarify)
needs-triage → ready-for-agent (fully specified, agent-safe)
needs-triage → ready-for-human (needs human work)
needs-triage → wontfix (will not action)
needs-info → needs-triage (reporter responded, re-evaluate)
ready-for-agent → ready-for-human (agent couldn't complete)
ready-for-human → ready-for-agent (spec improved, now agent-safe)
```

## Creating labels

If labels don't exist yet, create them with:

```bash
gh label create "needs-triage" --description "Needs maintainer evaluation" --color "FBCA04"
gh label create "needs-info" --description "Waiting on reporter for more details" --color "0E8A16"
gh label create "ready-for-agent" --description "Fully specified, ready for AI agent" --color "1D76DB"
gh label create "ready-for-human" --description "Needs human implementation" --color "B60205"
gh label create "wontfix" --description "Will not be actioned" --color "000000"
```
