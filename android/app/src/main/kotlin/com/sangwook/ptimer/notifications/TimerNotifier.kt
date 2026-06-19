package com.sangwook.ptimer.notifications

/**
 * Notification boundary. Completion fires exactly once per completion (driven
 * by the tick loop's newly-completed ids); the ongoing notification tracks the
 * representative running timer (Android equivalent of the iOS lock-screen Live
 * Activity).
 */
interface TimerNotifier {
    /**
     * Post a completion notification. [name] is the primary timer identity
     * (e.g. "Camera 1 · Velvia 50"); [subtitle] is the optional source line
     * (e.g. "Corrected Exposure · …") shown as the body, so corrected / custom /
     * limited-guidance source identity is not lost when a timer completes
     * through the scheduled alarm.
     */
    fun postCompletion(id: String, name: String, subtitle: String? = null)
    fun showOngoing(name: String, remainingLabel: String)
    fun clearOngoing()
}

/** No-op notifier for tests / previews. */
object NoOpTimerNotifier : TimerNotifier {
    override fun postCompletion(id: String, name: String, subtitle: String?) {}
    override fun showOngoing(name: String, remainingLabel: String) {}
    override fun clearOngoing() {}
}
