# Spec Delta

## REMOVED Requirements

### Requirement: Consumers keep their current progress source
**Reason**: `retire-tracker-token` switches advice, raid timers and task state to local progress and removes the token.
**Migration**: Manual level, loyalty, station and task values now feed advice and the scav cooldown through local progress (progress-authority, raid-timers).
