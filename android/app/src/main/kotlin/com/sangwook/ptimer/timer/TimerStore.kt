package com.sangwook.ptimer.timer

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

/** Persistence boundary for the timer collection JSON blob. */
interface TimerStore {
    suspend fun load(): String?
    suspend fun save(json: String)
    suspend fun clear()
}

/** In-memory store for tests / previews. */
class InMemoryTimerStore(@Volatile private var value: String? = null) : TimerStore {
    override suspend fun load(): String? = value
    override suspend fun save(json: String) { value = json }
    override suspend fun clear() { value = null }
}

private val Context.timerDataStore by preferencesDataStore("ptimer_timers")

/** DataStore-backed timer store. */
class DataStoreTimerStore(private val context: Context) : TimerStore {
    private val key = stringPreferencesKey("timers_json")

    override suspend fun load(): String? = context.timerDataStore.data.map { it[key] }.first()
    override suspend fun save(json: String) { context.timerDataStore.edit { it[key] = json } }
    override suspend fun clear() { context.timerDataStore.edit { it.remove(key) } }
}
