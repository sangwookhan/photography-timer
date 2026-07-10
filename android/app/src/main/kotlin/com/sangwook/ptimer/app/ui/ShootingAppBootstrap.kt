// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui

import android.content.Context
import com.sangwook.ptimer.app.persistence.AppPersistenceWriter
import com.sangwook.ptimer.app.persistence.AsyncWriteCustomFilmLibraryStore
import com.sangwook.ptimer.app.persistence.DataStoreCustomFilmLibraryStore
import com.sangwook.ptimer.app.persistence.DataStoreDisplaySettingsStore
import com.sangwook.ptimer.app.persistence.DataStoreSlotSessionStore
import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogV2
import com.sangwook.ptimer.core.customfilm.CustomFilmLibrary
import com.sangwook.ptimer.core.exposure.NDNotationMode
import com.sangwook.ptimer.core.persistence.PersistentSlotSession
import com.sangwook.ptimer.core.reciprocity.FilmIdentity

/**
 * Everything [ShootingApp] needs that used to block the main thread during
 * first composition: the bundled catalog parse and every initial DataStore
 * read (PTIMER-217). [load] runs off the main thread — MainActivity invokes it
 * on `Dispatchers.IO` behind the splash — so composition receives ready values
 * and performs no blocking read of its own.
 *
 * The store reads run on the shared persistence writer, so a configuration-
 * change reload observes every write the replaced generation submitted rather
 * than racing a not-yet-committed one. The stores created for the reads are
 * carried along so ShootingApp reuses the same instances for its writes.
 */
class ShootingAppBootstrap(
    /**
     * The bundled catalog's user-selectable films. Reading this inside [load]
     * forces the catalog's lazy JSON parse off the main thread; later accesses
     * of `LaunchPresetFilmCatalogV2.userSelectableFilms` (the same list
     * instance) are cached and stay cheap on main.
     */
    val presetFilms: List<FilmIdentity>,
    /** Custom film library, constructor-loaded from its store during [load]. */
    val library: CustomFilmLibrary,
    val initialSession: PersistentSlotSession?,
    val slotStore: DataStoreSlotSessionStore,
    val displaySettingsStore: DataStoreDisplaySettingsStore,
    val initialNdNotationMode: NDNotationMode,
    val initialExactAlarmWarningDismissed: Boolean,
) {
    companion object {
        /**
         * Loads off the main thread. The caller runs this on `Dispatchers.IO`
         * (so the catalog parse stays off-main); the DataStore reads — including
         * the library's constructor load — then run through the shared writer's
         * ordered read, so on a configuration-change reload they wait behind any
         * write the replaced generation already submitted (PTIMER-217).
         */
        suspend fun load(context: Context): ShootingAppBootstrap {
            val slotStore = DataStoreSlotSessionStore.create(context)
            val displaySettingsStore = DataStoreDisplaySettingsStore.create(context)
            // Library writes happen in main-thread UI callbacks; the async-write
            // decorator keeps those callbacks non-blocking (PTIMER-217).
            val libraryStore = AsyncWriteCustomFilmLibraryStore(DataStoreCustomFilmLibraryStore.create(context))
            // Catalog parse is CPU, not a store read — no ordering needed; it runs
            // off-main on the caller's IO dispatcher before the ordered reads.
            val presetFilms = LaunchPresetFilmCatalogV2.userSelectableFilms
            return AppPersistenceWriter.readOrdered {
                ShootingAppBootstrap(
                    presetFilms = presetFilms,
                    library = CustomFilmLibrary(store = libraryStore),
                    initialSession = slotStore.loadSession(),
                    slotStore = slotStore,
                    displaySettingsStore = displaySettingsStore,
                    initialNdNotationMode = displaySettingsStore.loadNdNotationMode(),
                    initialExactAlarmWarningDismissed = displaySettingsStore.loadExactAlarmWarningDismissed(),
                )
            }
        }
    }
}
