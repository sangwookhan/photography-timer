// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui

/**
 * Marks an instrumented case that exercises accessibility behavior
 * (announcement events, accessibility actions or focus, accessibility-only
 * semantics). Run ordinary instrumented suites with
 * `-Pandroid.testInstrumentationRunnerArguments.notAnnotation=com.sangwook.ptimer.app.ui.AccessibilityTest`
 * so these cases stay out of a broad run; they are run only in a separately
 * approved accessibility pass.
 */
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.FUNCTION, AnnotationTarget.CLASS)
annotation class AccessibilityTest
