plugins {
    id("org.jetbrains.kotlin.jvm")
    id("org.jetbrains.kotlin.plugin.serialization")
}

// Pure-Kotlin JVM module: the PTimer domain/core engine. No Android
// dependency is declared here, which mechanically enforces the
// "no framework in domain" boundary (the iOS PTimerCore analogue).
kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    testImplementation("junit:junit:4.13.2")
}
