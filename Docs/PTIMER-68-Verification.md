# PTIMER-68 Verification

## 기능 시험 절차

1. 알림 권한을 허용한 상태에서 앱을 실행한다.
2. timer를 시작하고 앱을 background로 보낸 뒤, completion 시각에 local notification이 정확히 1회 표시되는지 확인한다.
3. timer를 시작하고 기기를 lock screen 상태로 둔 뒤, completion 시각에 local notification이 정확히 1회 표시되는지 확인한다.
4. 같은 timer 완료 후 앱을 다시 열어도 duplicate alert가 추가로 발생하지 않는지 확인한다.
5. timer를 시작한 뒤 중간에 stop 하면 예정된 completion notification이 취소되고, 원래 completion 시각이 지나도 알림이 오지 않는지 확인한다.
6. stop 한 timer를 resume 하면 새 endDate 기준으로 notification이 다시 예약되고, 새 completion 시각에만 1회 알림이 오는지 확인한다.
7. timer를 remove 하거나 completed timer를 clear 한 뒤 관련 pending notification이 정리되어 추가 알림이 오지 않는지 확인한다.
8. 여러 timer를 동시에 시작했을 때 각 timer가 자기 completion 시각에 맞춰 개별적으로 1회씩만 알림되는지 확인한다.
9. 앱이 foreground active 상태일 때 timer가 완료되면 기존 PTIMER-66 sound/haptic feedback은 유지되고, 이후 stale local notification이 별도로 오지 않는지 확인한다.
10. 알림 권한이 거부된 상태에서도 foreground completion sound/haptic은 계속 동작하는지 확인한다.

## Commit Verification

- Verify local notification is delivered exactly once when a running timer completes in the background and while the device is locked.
- Verify stopped, removed, and cleared timers cancel pending completion notifications.
- Verify resumed timers reschedule against the new end date without duplicate delivery.
- Verify PTIMER-66 foreground sound and haptic feedback still works independently, and no stale local notification is delivered after foreground completion.
