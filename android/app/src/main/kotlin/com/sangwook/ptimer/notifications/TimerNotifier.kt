package com.sangwook.ptimer.notifications

/**
 * Notification boundary. Completion fires exactly once per completion (driven
 * by the tick loop's newly-completed ids); the ongoing notification tracks the
 * representative running timer (Android equivalent of the iOS lock-screen Live
 * Activity).
 */
interface TimerNotifier {
    fun postCompletion(id: String, name: String)
    fun showOngoing(name: String, remainingLabel: String)
    fun clearOngoing()
}

/** No-op notifier for tests / previews. */
object NoOpTimerNotifier : TimerNotifier {
    override fun postCompletion(id: String, name: String) {}
    override fun showOngoing(name: String, remainingLabel: String) {}
    override fun clearOngoing() {}
}
