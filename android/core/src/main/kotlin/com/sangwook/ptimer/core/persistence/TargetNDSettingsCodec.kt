// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.persistence

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

object TargetNDSettingsCodec {
    private val json = Json { ignoreUnknownKeys = true }
    fun decode(raw: String): PersistentTargetNDSettings? = runCatching { json.decodeFromString<PersistentTargetNDSettings>(raw) }.getOrNull()
    fun encode(settings: PersistentTargetNDSettings): String = json.encodeToString(settings)
}
