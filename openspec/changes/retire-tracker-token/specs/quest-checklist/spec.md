# Spec Delta

## REMOVED Requirements

### Requirement: Advice stays on the Tracker token
**Reason**: `retire-tracker-token` switches advice, raid timers and task state to local progress and removes the token.
**Migration**: Ticking objectives and counters now feeds advice through local progress (progress-authority).
