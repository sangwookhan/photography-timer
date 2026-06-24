package com.sangwook.ptimer.app.persistence

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.sangwook.ptimer.core.persistence.CustomFilmLibraryCodec
import com.sangwook.ptimer.core.persistence.CustomFilmLibraryStoring
import com.sangwook.ptimer.core.persistence.PersistentCustomFilmLibrarySnapshot
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.runBlocking

private val Context.customFilmLibraryDataStore by preferencesDataStore(name = "custom_film_library")
private val LIBRARY_KEY = stringPreferencesKey("custom_film_library_json")

/**
 * DataStore-backed [CustomFilmLibraryStoring]. Persists the custom film
 * library as the codec's JSON string under a single Preferences key. Writes
 * are infrequent (only on create/delete), so the bridged blocking write is
 * negligible; decode is fail-safe so a corrupt store reads as empty.
 */
class DataStoreCustomFilmLibraryStore(private val context: Context) : CustomFilmLibraryStoring {

    override fun loadSnapshot(): PersistentCustomFilmLibrarySnapshot? = runBlocking {
        val prefs = context.customFilmLibraryDataStore.data.firstOrNull()
        val json = prefs?.get(LIBRARY_KEY) ?: return@runBlocking null
        CustomFilmLibraryCodec.decode(json)
    }

    override fun saveSnapshot(snapshot: PersistentCustomFilmLibrarySnapshot) {
        runBlocking {
            context.customFilmLibraryDataStore.edit { it[LIBRARY_KEY] = CustomFilmLibraryCodec.encode(snapshot) }
        }
    }

    override fun clearSnapshot() {
        runBlocking { context.customFilmLibraryDataStore.edit { it.remove(LIBRARY_KEY) } }
    }
}
