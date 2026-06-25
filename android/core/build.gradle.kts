plugins {
    id("org.jetbrains.kotlin.jvm")
    id("org.jetbrains.kotlin.plugin.serialization")
}

// Pure-Kotlin domain module — the Android analogue of iOS PTimerCore.
// It owns exposure/reciprocity/timer calculation, catalog loading, and
// persistence schemas. It must NOT depend on the Android SDK; that boundary
// is enforced mechanically by this module's classpath (no com.android.* /
// androidx.* plugins or dependencies here).

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    testImplementation("junit:junit:4.13.2")
}

tasks.withType<Test> {
    useJUnit()
}
