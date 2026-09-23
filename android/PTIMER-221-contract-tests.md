# PTIMER-221 Android contract test map

Which automated test asserts which requirement of the Filter Sets
capability contract (`docs/specs/calculator/filter-sets.md`, merged
revision `64565f73`).

Scope: the Android `:core` and `:app` modules. Test names are fully
qualified. Kotlin test functions whose names contain spaces are
declared with backticks in the source; those backticks are omitted
here. Modules and source sets:

- `:core` unit — `android/core/src/test/kotlin`
- `:app` unit — `android/app/src/test/kotlin`
- `:app` instrumented — `android/app/src/androidTest/kotlin`
  (Compose, emulator; run with `:app:connectedDebugAndroidTest`)

A requirement is listed against a test only when that test actually
asserts the requirement's behavior. Clauses no test asserts are called
out as **manual only** with the verification step that covers them.

---

## Filter-set management

### FILTER-SET-001 — one management surface; distinct exit-edit control; delete bound to the stable id

- `com.sangwook.ptimer.app.vm.FilterInventoryModelTest.creationAppendsToTheUserDefinedOrderAndRejectsABlankName`
- `com.sangwook.ptimer.app.vm.FilterInventoryModelTest.renameAndRecolorKeepTheStableIdAndSkipNoOps`
- `com.sangwook.ptimer.app.vm.FilterInventoryModelTest.moveReordersWithoutChangingIds`
- `com.sangwook.ptimer.app.vm.FilterInventoryModelTest.deleteRemovesTheSetAndItsItems`
- `com.sangwook.ptimer.app.vm.FilterSetRenameCommitTest.aDeletedSetIsANoOp`
- `com.sangwook.ptimer.app.vm.FilterSetRenameCommitTest.aBlankDraftRestoresTheCurrentName`
- `com.sangwook.ptimer.app.vm.FilterSetRenameCommitTest.anUnchangedDraftDoesNothingEvenWithSurroundingWhitespace`
- `com.sangwook.ptimer.app.vm.FilterSetRenameCommitTest.anythingElseRenamesToTheTrimmedDraft`
- `com.sangwook.ptimer.app.vm.FilterSourcePlusGestureArbiterTest.a stationary hold opens management and the release adds nothing` — the Plus long-press entry
- `com.sangwook.ptimer.app.ui.shooting.FilterSetManagementEditControlTest.emptyList_showsCloseAndNewButNoEditControl` — no no-op Edit on an empty list; Close and New stay
- `com.sangwook.ptimer.app.ui.shooting.FilterSetManagementEditControlTest.editControl_appearsWithTheFirstSetAndLeavesWithTheLastOne` — Edit appears with the first set, is worded apart from Close, and leaves (ending edit mode) with the last set; the delete confirmation names the targeted Filter Set

Manual only: the persistent ND-header entry remaining available while the
stack already holds four wheels. Verify on the emulator — fill the stack
to four wheels and confirm the header gear still opens the surface.

### FILTER-SET-002 — stable id, non-empty name, required color, display position

- `com.sangwook.ptimer.app.vm.FilterInventoryModelTest.renameAndRecolorKeepTheStableIdAndSkipNoOps`
- `com.sangwook.ptimer.app.vm.FilterInventoryModelTest.moveReordersWithoutChangingIds`
- `com.sangwook.ptimer.app.vm.FilterInventoryModelTest.creationAppendsToTheUserDefinedOrderAndRejectsABlankName`

### FILTER-SET-003 — suggested creation color differs from the previous suggestion

- `com.sangwook.ptimer.core.exposure.FilterInventoryTest.colorSuggestionDiffersFromPreviousSuggestion`
- `com.sangwook.ptimer.app.vm.FilterInventoryModelTest.consecutiveColorSuggestionsDiffer`

### FILTER-SET-004 — Standard first, then Filter Sets in user-defined order

- `com.sangwook.ptimer.core.exposure.FilterStackTest.equalSubtotalsPutStandardFirstThenFilterSetUserOrder`
- `com.sangwook.ptimer.app.vm.FilterInventoryModelTest.creationAppendsToTheUserDefinedOrderAndRejectsABlankName` — a new set appends to that order

Manual only: the Plus wheel's browsing order as rendered. Verify by
dragging the Plus control through the sources on the emulator.

### FILTER-SET-005 — names and colors are presentation only

- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.theCapturedSummaryAndReferenceSurviveLaterRenames`
- `com.sangwook.ptimer.app.vm.FilterWheelPresenterTest.sourceNameUsesCanonicalEnglish`

Manual only: "color shall never be the only means of identification" in
the rendered surfaces. Verify with TalkBack on the Filter Set list and
the wheel source cues (each carries its name text beside the swatch).

---

## Physical filter inventory and conversion

### FILTER-ITEM-001 — add, edit, reorder, delete items

- `com.sangwook.ptimer.app.vm.FilterInventoryModelTest.addAppendsAndADuplicateIdReplacesInPlace`
- `com.sangwook.ptimer.app.vm.FilterInventoryModelTest.updateReplacesWhereverTheItemLivesAndSkipsAnUnchangedSave`
- `com.sangwook.ptimer.app.vm.FilterInventoryModelTest.moveItemAndDeleteItemActOnTheOwningSetOnly`

### FILTER-ITEM-002 — stable item id, non-empty name, equal items stay distinct

- `com.sangwook.ptimer.core.exposure.FilterInventoryTest.equalItemsRemainDistinctById`
- `com.sangwook.ptimer.core.exposure.FilterStackTest.twoEqualItemsSumWhileASecondSelectionOfEitherIsUnavailable`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.twoEqualItemsMountTogetherWhileASecondSelectionOfOneIsRejected`
- `com.sangwook.ptimer.app.vm.FilterItemEditorDraftTest.aBlankNameBlocksSaveEvenWithAValidValue`

### FILTER-ITEM-003 — the kind is chosen explicitly, never inferred

- `com.sangwook.ptimer.app.vm.FilterItemEditorDraftTest.theKindDecidesWhetherTheValueBecomesFixedOrGnd`
- `com.sangwook.ptimer.app.vm.FilterItemEditorSessionMemoryTest.startsInStopsAndAlwaysStartsAsFixed`

### FILTER-ITEM-004 — decimal value in Stops / OD / ND factor and its canonical conversion

- `com.sangwook.ptimer.core.exposure.FilterInventoryTest.stopsValueIsUnchanged`
- `com.sangwook.ptimer.core.exposure.FilterInventoryTest.opticalDensityDividesByPointThree`
- `com.sangwook.ptimer.core.exposure.FilterInventoryTest.filterFactorMatchingACommercialLabelTakesTheLadderValue`
- `com.sangwook.ptimer.core.exposure.FilterInventoryTest.filterFactorWithoutACommercialLabelUsesLog2`
- `com.sangwook.ptimer.core.exposure.FilterInventoryTest.invalidRegisteredValuesAreRejected`
- `com.sangwook.ptimer.core.exposure.FilterStackTest.nd1000ContributesExactlyTenStopsThroughSumSortAndCap`
- `com.sangwook.ptimer.app.vm.FilterItemEditorDraftTest.opticalDensityDividesByPointThree`
- `com.sangwook.ptimer.app.vm.FilterItemEditorDraftTest.commercialNdFactorUsesTheLadderValue`
- `com.sangwook.ptimer.app.vm.FilterItemEditorDraftTest.zeroAndOverThirtyStopsAreRefused`
- `com.sangwook.ptimer.app.vm.FilterItemEditorDraftTest.aCommaDecimalSeparatorParses`
- `com.sangwook.ptimer.app.vm.FilterItemEditorDraftTest.anUntouchedValueFieldIsNotYetAnError`
- `com.sangwook.ptimer.app.vm.FilterItemEditorDraftTest.editingSeedsTheRegisteredValueAndUnit`

### FILTER-ITEM-005 — editing updates every stack; a conflicting save stays uncommitted

- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.editingAnItemUpdatesEveryStackAndIsBlockedByTheCap`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.removingASelectedCplChoiceIsBlockedAndNamesEveryAffectedCamera`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.changingAMountedItemsKindIsBlockedLikeARemovedRow`
- `com.sangwook.ptimer.app.vm.FilterInventoryModelTest.addAndUpdateRejectAMalformedItem`

### FILTER-ITEM-006 — deleting an item or a Filter Set

- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.deletingAnItemEmptiesItsWheelsOnEveryCamera`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.deletingAFilterSetRemovesItsWheelsAndFallsBackToStandard`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.theCapturedSummaryAndReferenceSurviveLaterRenames` — captured snapshots do not change
- `com.sangwook.ptimer.app.vm.FilterInventoryModelTest.deleteRemovesTheSetAndItsItems`

### FILTER-ITEM-007 — editor-session notation memory

- `com.sangwook.ptimer.app.vm.FilterItemEditorSessionMemoryTest.startsInStopsAndAlwaysStartsAsFixed`
- `com.sangwook.ptimer.app.vm.FilterItemEditorSessionMemoryTest.savingANewFixedOrGndItemRemembersItsNotation`
- `com.sangwook.ptimer.app.vm.FilterItemEditorSessionMemoryTest.savingANewCplItemLeavesTheNotationUnchanged`

Manual only: the memory resetting when the Filter Set editor is closed
or the app restarts (the memory object is `remember`-keyed on the set).
Verify by leaving and re-entering the Filter Set editor.

---

## CPL exposure-loss choices

### FILTER-CPL-001 — three fields, new items start at 1 / 1.5 / 2

- `com.sangwook.ptimer.core.exposure.FilterInventoryTest.defaultChoicesAreOneOnePointFiveTwo`
- `com.sangwook.ptimer.app.vm.FilterItemEditorDraftTest.newCplChoicesStartAtOneOnePointFiveAndTwo`

### FILTER-CPL-002 — one fractional digit, 0.1–9.9, at least one valid, duplicates collapse

- `com.sangwook.ptimer.core.exposure.FilterInventoryTest.choiceRangeAndPrecision`
- `com.sangwook.ptimer.core.exposure.FilterInventoryTest.emptyFieldsOmitChoicesAndDuplicatesCollapse`
- `com.sangwook.ptimer.core.exposure.FilterInventoryTest.atLeastOneValidChoiceIsRequired`
- `com.sangwook.ptimer.core.exposure.FilterInventoryTest.cplFieldParsingNormalizesSeparatorsAndRejectsOutOfRule`
- `com.sangwook.ptimer.core.exposure.FilterInventoryTest.generalDecimalParsing`
- `com.sangwook.ptimer.app.vm.FilterItemEditorDraftTest.aTwoDecimalChoiceIsRefusedOnItsOwnField`
- `com.sangwook.ptimer.app.vm.FilterItemEditorDraftTest.aChoiceOutsideTheRangeIsRefused`
- `com.sangwook.ptimer.app.vm.FilterItemEditorDraftTest.allEmptyFieldsAreRefused`
- `com.sangwook.ptimer.app.vm.FilterItemEditorDraftTest.oneValidChoiceIsEnoughAndEmptyFieldsAreSkipped`
- `com.sangwook.ptimer.app.vm.FilterItemEditorDraftTest.theValueErrorNeverFiresWhileTheKindIsCpl`

### FILTER-CPL-003 — decimal-capable numeric keyboard

**Manual only.** The keyboard type is a `KeyboardOptions` declaration
with no automated assertion. Verify on the emulator: focus each CPL
choice field in the item editor and confirm a decimal keypad appears.
The separator/paste normalization half of the requirement is covered by
the FILTER-CPL-002 tests above.

### FILTER-CPL-004 — editor explanatory copy, equivalent in English and Korean

**Manual only.** Verify by reading `values/strings.xml` and
`values-ko/strings.xml` for the CPL footer copy.

### FILTER-CPL-005 — CPL rows are the distinct choices; siblings disable across wheels

- `com.sangwook.ptimer.core.exposure.FilterStackTest.cplRowsAreDistinctChoicesAndSiblingsDisableEveryRowOfTheItem`
- `com.sangwook.ptimer.app.vm.FilterWheelPresenterTest.cplChoicesStayExposureLossInStopsInEveryNotation`

---

## GND recording and calculation

### FILTER-GND-001 — Record only contributes 0, Apply full value contributes the registered stops

- `com.sangwook.ptimer.core.exposure.FilterStackTest.gndRecordOnlyContributesZeroAndApplyFullContributesRegisteredValue`
- `com.sangwook.ptimer.app.vm.FilterWheelPresenterTest.gndShowsItsRegisteredDensityInBothModesWithTheGndCategory`

### FILTER-GND-002 — mode change is scoped to that wheel on the active camera

- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.aGndModeSwitchDoesNotTouchAnotherCamera`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.aGndModeSwitchChangesTheContributionButNotTheGroupPosition`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.theCapturedSummaryAndReferenceSurviveLaterRenames` — an already-started timer is unaffected

Manual only: "Record only shall be the default when a GND is first
selected." No test asserts the initially selected row of a freshly
mounted GND. Verify on the emulator by mounting a GND item and reading
the wheel's mode label.

### FILTER-GND-003 — metering warning copy

**Manual only.** Verify the Apply-full-value warning text in the item
editor / detail surface.

### FILTER-GND-004 — no partial-density estimation

- `com.sangwook.ptimer.core.exposure.FilterStackTest.gndRecordOnlyContributesZeroAndApplyFullContributesRegisteredValue` — only the two contributions exist

---

## Mixed stack and filter wheels

### FILTER-STACK-001 — one to four actual wheels; Plus does not count

- `com.sangwook.ptimer.core.exposure.FilterStackTest.addUnavailabilityReasons`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.aFullStackRefusesAndReportsStackFull`
- `com.sangwook.ptimer.app.vm.NdWheelStackControllerTest.startsWithASingleZeroWheelAndNonIndexIdentity`
- `com.sangwook.ptimer.app.vm.NdWheelStackControllerTest.addRefusedAtSaturationAndWhileAWheelMoves`

### FILTER-STACK-002 — Standard values may repeat; one item id once per camera

- `com.sangwook.ptimer.core.exposure.FilterStackTest.twoEqualItemsSumWhileASecondSelectionOfEitherIsUnavailable`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.twoEqualItemsMountTogetherWhileASecondSelectionOfOneIsRejected`
- `com.sangwook.ptimer.core.exposure.FilterStackTest.validatedRejectsOverCapDuplicateAndUnresolvedWheels`

### FILTER-STACK-003 — Empty plus the set's rows; Empty and Record only stay distinct

- `com.sangwook.ptimer.core.exposure.FilterStackTest.emptyAndRecordOnlyAreDistinctStates`
- `com.sangwook.ptimer.app.vm.FilterWheelPresenterTest.emptyRendersCanonicalZeroThroughTheSharedStandardFormatter`

### FILTER-STACK-004 — effective sum, the 30-stop cap, and the sighted traversal fallback

- `com.sangwook.ptimer.core.exposure.FilterStackTest.recordOnlyRemainsAddableAtCapAndEnablingContributionIsRejected`
- `com.sangwook.ptimer.core.exposure.FilterStackTest.standardRowsAreTruncatedToTheRemainingBudget`
- `com.sangwook.ptimer.core.exposure.FilterStackTest.nd1000ContributesExactlyTenStopsThroughSumSortAndCap`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.aSettleOnAMountedRowFallsBackToTheNearestTraversedSelectableRow`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.theFallbackSkipsEveryUnavailableRowItTraverses`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.noSelectableTraversedRowKeepsThePreviousSelectionAndShowsTheReason`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.theFallbackNeverSearchesBeyondTheAttemptedRowOrWraps`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.anOverCapSettleFallsBackTheSameWay`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.anAssistiveCommitGetsNoSightedFallback`
- `com.sangwook.ptimer.app.vm.NdWheelStackControllerTest.overBudgetSelectionIsRejectedInSettleOrder`
- `com.sangwook.ptimer.app.vm.NdWheelStackControllerTest.overBudgetRejectionFollowsSettleOrderNotChangeOrder`
- `com.sangwook.ptimer.app.ui.shooting.FilterStackInteractionTest.refusedSettle_returnsTheViewportToTheCommittedRow` — a refused settle leaves the viewport on the committed row, with the total and selection unchanged

### FILTER-STACK-005 — contiguous source groups sorted by registered subtotal descending

- `com.sangwook.ptimer.core.exposure.FilterStackTest.sourceGroupsSortByRegisteredSubtotalAndStayContiguous`
- `com.sangwook.ptimer.core.exposure.FilterStackTest.equalSubtotalsPutStandardFirstThenFilterSetUserOrder`
- `com.sangwook.ptimer.core.exposure.FilterStackTest.standardSelectionCanReorderGroupsOnlyThroughItsSubtotal`
- `com.sangwook.ptimer.core.exposure.FilterStackTest.withinSourceSortIsDescendingWithEmptyLast`
- `com.sangwook.ptimer.core.exposure.FilterStackTest.cplSortsByItsSelectedChoiceAndGndByRegisteredDensityInBothModes`
- `com.sangwook.ptimer.core.exposure.FilterStackTest.gndModeSwitchNeverMovesItsGroupWhileACplChoiceMayAfterSettlement`
- `com.sangwook.ptimer.core.exposure.FilterStackTest.addingAWheelNeverChangesTheEffectiveValue`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.sourceGroupsSortByRegisteredSubtotalAndStayContiguous`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.aGndModeSwitchChangesTheContributionButNotTheGroupPosition`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.addingAStandardWheelReturnsAGroupedAndSortedStack`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.anAddedWheelJoinsItsSourceGroupImmediately`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.anAddedWheelSortsLastInsideItsOwnGroup`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.anAdditionWhileOrderingIsSuspendedDefersToTheSingleReconciliation`
- `com.sangwook.ptimer.app.vm.NdWheelStackControllerTest.commitSortsDescendingAndIdentityFollowsThePermutation`
- `com.sangwook.ptimer.app.ui.shooting.FilterStackInteractionTest.addedWheel_appearsInItsSettledSourceGroupWithoutFurtherInteraction`

Manual only: the presentation movement itself — every wheel staying
visible and each stable identity animating directly to its new position,
and a newer arrangement retargeting an in-flight animation. Verify on
the emulator by committing a value that reorders a four-wheel stack.

### FILTER-STACK-006 — narrowed idle cleanup for the mixed stack

- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.cleanupRemovesEmptyWheelsButKeepsAMountedRecordOnlyGnd`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.saturationShedsOnlyTheWheelThatCanHoldNoUsableRow`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.onlyAnActualRemovalPublishesAnEvent`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.aRecordOnlyItemKeepsItsSourceAddableAtThirtyStops`
- `com.sangwook.ptimer.app.vm.NdWheelStackControllerTest.cleanupJudgmentRequiresAQuietMachine`
- `com.sangwook.ptimer.app.vm.NdWheelStackControllerTest.saturatedSetShedsLeftoverZerosInTheSameCommit`
- `com.sangwook.ptimer.app.vm.NdWheelStackControllerTest.ownedTimerCleansAnUntouchedZeroAfterTheGracePeriod`
- `com.sangwook.ptimer.app.vm.NdWheelStackControllerTest.ownedTimerDefersUnderAFingerThenCleansOnTheNextFire`
- `com.sangwook.ptimer.app.vm.NdWheelStackControllerTest.structuralChangeRestartsTheGracePeriodForNewZeros`
- `com.sangwook.ptimer.app.vm.NdWheelStackControllerTest.fireTimeCleanupRunsOnlyWhenQuiet`
- `com.sangwook.ptimer.app.vm.NdWheelStackControllerTest.cleanupRemovesAllZerosButKeepsOneWheelWhenAllZero`

Manual only: the spoken wording of the removal announcement while a
screen reader is active (`announceForAccessibility`). Verify with
TalkBack on the emulator.

### FILTER-STACK-007 — quiet viewport; one candidate identified everywhere

- `com.sangwook.ptimer.app.vm.FilterWheelPresenterTest.fixedValuesFollowTheGlobalNotationNumericComponentOnly`
- `com.sangwook.ptimer.app.vm.FilterWheelPresenterTest.standardRowsUseTheLadderValueAndTheNdCategory`
- `com.sangwook.ptimer.app.vm.FilterWheelPresenterTest.decimalRenderingTrimsTrailingZeros`
- `com.sangwook.ptimer.app.vm.FilterWheelPresenterTest.unavailableRowsCarryTheirReason`
- `com.sangwook.ptimer.app.vm.FilterStatusRegionPresenterTest.a moving wheel outranks the idle summary`
- `com.sangwook.ptimer.app.ui.shooting.FilterStackInteractionTest.refusedSettle_returnsTheViewportToTheCommittedRow` — at rest the viewport shows the committed row

Manual only: the rendered visual quietness (centered value size, per-row
type rail, persistent label) during touch, drag, and inertial settling.
Verify on the emulator.

### FILTER-STACK-008 — one stable status region, leading summary and trailing total

- `com.sangwook.ptimer.app.vm.FilterStatusRegionPresenterTest.a rejection outranks browsing and movement and holds as a warning`
- `com.sangwook.ptimer.app.vm.FilterStatusRegionPresenterTest.browsing outranks movement and the idle summary`
- `com.sangwook.ptimer.app.vm.FilterStatusRegionPresenterTest.a moving wheel outranks the idle summary`
- `com.sangwook.ptimer.app.vm.FilterStatusRegionPresenterTest.the idle summary is held at secondary emphasis`
- `com.sangwook.ptimer.app.vm.FilterStatusRegionPresenterTest.a Standard-only stack shows the total alone and lets it fade`
- `com.sangwook.ptimer.app.vm.FilterStatusRegionPresenterTest.a single Standard wheel at rest shows nothing`
- `com.sangwook.ptimer.app.ui.shooting.FilterStatusRegionLayoutTest.idleContent_putsTheSummaryLeadingAndTheTotalTrailing`
- `com.sangwook.ptimer.app.ui.shooting.FilterStatusRegionLayoutTest.movingContent_putsTheRowDetailLeadingAndTheTotalTrailing`
- `com.sangwook.ptimer.app.ui.shooting.FilterStatusRegionLayoutTest.rejectionContent_putsTheReasonLeadingAndTheTotalTrailing`
- `com.sangwook.ptimer.app.ui.shooting.FilterStatusRegionLayoutTest.anOverflowingSummaryYieldsSpaceWhileTheTotalKeepsItsFullWidth`

Manual only:

- the composition of the idle source summary itself — one entry per
  source in settled group order, with a `×N` count when a source owns
  more than one wheel, and each Filter Set name carrying its color cue.
  The presenter tests pass a prepared summary in and assert only its
  priority. Verify on the emulator with a `NiSi kit · Lee holder ×2 ·
  Standard` stack.
- the reserved one-row height being returned to the wheel row and
  included in the density-tier fit calculation. Verify on the emulator
  at the largest supported text size.

---

## Plus wheel and per-camera source memory

### FILTER-PLUS-001 — long press vs. browse arbitration

- `com.sangwook.ptimer.app.vm.FilterSourcePlusGestureArbiterTest.a stationary release adds the displayed source`
- `com.sangwook.ptimer.app.vm.FilterSourcePlusGestureArbiterTest.a stationary hold opens management and the release adds nothing`
- `com.sangwook.ptimer.app.vm.FilterSourcePlusGestureArbiterTest.movement past the stationary tolerance cancels the long press`
- `com.sangwook.ptimer.app.vm.FilterSourcePlusGestureArbiterTest.browsing wins past the drag threshold and management never opens`
- `com.sangwook.ptimer.app.vm.FilterSourcePlusGestureArbiterTest.browsing clamps to the ends of the source list`
- `com.sangwook.ptimer.app.vm.FilterSourcePlusGestureArbiterTest.an opened long press ignores later movement`

### FILTER-PLUS-002 — expanded candidate label while moving; color cue at rest

- `com.sangwook.ptimer.app.vm.FilterStatusRegionPresenterTest.browsing outranks movement and the idle summary`

Manual only: the compact control's color tint at rest. Verify on the
emulator.

### FILTER-PLUS-003 — one direct gesture creates exactly one wheel

- `com.sangwook.ptimer.app.vm.FilterSourcePlusGestureArbiterTest.a stationary release adds the displayed source`
- `com.sangwook.ptimer.app.vm.FilterSourcePlusGestureArbiterTest.releasing on a different source adds that index once`
- `com.sangwook.ptimer.app.vm.FilterSourcePlusGestureArbiterTest.returning to the starting source adds nothing`
- `com.sangwook.ptimer.app.ui.shooting.FilterStackInteractionTest.addedWheel_appearsInItsSettledSourceGroupWithoutFurtherInteraction` — one tap adds exactly one wheel

### FILTER-PLUS-004 — per-camera memory of the last successful addition

- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.theRememberedSourceIsPerCameraAndAFreshCameraUsesStandard`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.aRefusedAddKeepsTheStackTheTotalAndTheRememberedSource`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.deletingAFilterSetRemovesItsWheelsAndFallsBackToStandard`
- `com.sangwook.ptimer.core.persistence.FilterStackPersistenceTest.mixedStackAndLastSourceSurviveRelaunch`

### FILTER-PLUS-005 — browsing stays enabled while adding is disabled with a reason

- `com.sangwook.ptimer.core.exposure.FilterStackTest.addUnavailabilityReasons`
- `com.sangwook.ptimer.core.exposure.FilterStackTest.recordOnlyRemainsAddableAtCapAndEnablingContributionIsRejected`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.aRecordOnlyItemKeepsItsSourceAddableAtThirtyStops`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.aRefusedAddKeepsTheStackTheTotalAndTheRememberedSource`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.aFullStackRefusesAndReportsStackFull`
- `com.sangwook.ptimer.app.vm.NdWheelStackControllerTest.addRefusedWhenNewWheelCouldHoldNoValue`
- `com.sangwook.ptimer.app.vm.NdWheelStackControllerTest.addRefusedAtSaturationAndWhileAWheelMoves`
- `com.sangwook.ptimer.app.vm.NdWheelStackControllerTest.wiggleAndReturnReleaseRestoresAddAvailability`

---

## Persistence and captured context

### FILTER-PERSIST-001 — additive, backward-compatible persistence of inventory, stacks, and last source

- `com.sangwook.ptimer.core.persistence.FilterStackPersistenceTest.mixedStackAndLastSourceSurviveRelaunch`
- `com.sangwook.ptimer.core.persistence.FilterStackPersistenceTest.downgradeFieldsCarryStandardWheelsOnly`
- `com.sangwook.ptimer.core.persistence.FilterStackPersistenceTest.aStackWithoutStandardWheelsStillDegradesToOneStandardZeroWheel`
- `com.sangwook.ptimer.core.persistence.FilterStackPersistenceTest.aLegacyPayloadWithoutTheFilterKeysRestoresTheStandardStack`
- `com.sangwook.ptimer.core.persistence.FilterStackPersistenceTest.aLegacyScalarOnlyPayloadRestoresOneStandardWheel`
- `com.sangwook.ptimer.core.persistence.FilterInventoryCodecTest.inventoryRoundTripsThroughTheCodec`
- `com.sangwook.ptimer.app.persistence.DataStoreFilterInventoryStoreTest.roundTripsIdsNamesColorsOrderAndItems`
- `com.sangwook.ptimer.app.vm.FilterInventoryModelTest.everyMutationRoundTripsThroughThePersistedSnapshot`
- `com.sangwook.ptimer.app.vm.ShootingAppViewModelTest.theRetainedFilterInventoryIsTheOneTheCalculatorReconcilesAndItPersistsThroughTheWriter`
- `com.sangwook.ptimer.app.vm.NdWheelStackControllerTest.stackPersistsAndLegacyScalarCarriesTheMaximumWheel`

### FILTER-PERSIST-002 — independent decoding and safe degradation

- `com.sangwook.ptimer.core.persistence.FilterInventoryCodecTest.aMalformedItemIsSkippedWhileItsFilterSetSurvives`
- `com.sangwook.ptimer.core.persistence.FilterInventoryCodecTest.anUnknownColorRestoresAsTheDefault`
- `com.sangwook.ptimer.core.persistence.FilterInventoryCodecTest.aMalformedFilterSetIsDroppedAndTheOutcomeDegrades`
- `com.sangwook.ptimer.core.persistence.FilterInventoryCodecTest.duplicateFilterSetIdsCollapseFirstWins`
- `com.sangwook.ptimer.core.persistence.FilterInventoryCodecTest.duplicateItemIdsCollapseFirstWins`
- `com.sangwook.ptimer.core.persistence.FilterInventoryCodecTest.unknownSchemaVersionAndMalformedRootAreRejected`
- `com.sangwook.ptimer.core.persistence.FilterInventoryCodecTest.blankIdsAndNamesAreSkippedOnRestore`
- `com.sangwook.ptimer.core.persistence.FilterStackPersistenceTest.anUnresolvedFilterSetIsDroppedAndAMissingItemBecomesEmpty`
- `com.sangwook.ptimer.core.persistence.FilterStackPersistenceTest.aRemovedCplChoiceRestoresAsEmptyNeverAnotherChoice`
- `com.sangwook.ptimer.core.persistence.FilterStackPersistenceTest.aCorruptedMixedStackFallsBackToTheLegacyStandardPath`
- `com.sangwook.ptimer.core.exposure.FilterStackTest.normalizationDropsUnknownSetsEmptiesUnknownItemsAndFallsBackToStandardZero`
- `com.sangwook.ptimer.core.exposure.FilterStackTest.normalizationRestoresAVanishedCplChoiceAsEmptyNeverAnotherChoice`
- `com.sangwook.ptimer.core.exposure.FilterStackTest.validatedRejectsOverCapDuplicateAndUnresolvedWheels`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.aStalePersistedCplChoiceRestoresAsEmpty`
- `com.sangwook.ptimer.app.persistence.DataStoreFilterInventoryStoreTest.missingKeyReadsAsNullRatherThanThrowing`
- `com.sangwook.ptimer.app.persistence.DataStoreFilterInventoryStoreTest.corruptPayloadFailsSafeToNullAndIsQuarantined`
- `com.sangwook.ptimer.app.persistence.DataStoreFilterInventoryStoreTest.secondFailureReplacesQuarantineAndANormalSaveKeepsIt`
- `com.sangwook.ptimer.app.persistence.DataStoreFilterInventoryStoreTest.clearRemovesTheLiveSnapshotAndItsQuarantine`
- `com.sangwook.ptimer.app.persistence.DataStoreFilterInventoryStoreTest.quarantineWriteFailureStillReturnsRecoveredFilterSets`
- `com.sangwook.ptimer.app.vm.NdWheelStackControllerTest.invalidPersistedStackFallsBackToTheLegacyScalar`

### FILTER-PERSIST-003 — immutable capture at timer start; descriptive reference string

- `com.sangwook.ptimer.core.exposure.FilterSummaryEntryTest.summaryCapturesSourceItemModeAndContribution`
- `com.sangwook.ptimer.core.timer.TimerIdentityFilterSummaryTest.summaryStoresRawTokensAndRoundTrips`
- `com.sangwook.ptimer.core.timer.TimerIdentityFilterSummaryTest.oneMalformedEntryIsDroppedAndTheTimerSurvives`
- `com.sangwook.ptimer.core.timer.TimerIdentityFilterSummaryTest.anUnknownOptionalTokenDegradesToNull`
- `com.sangwook.ptimer.core.timer.TimerIdentityFilterSummaryTest.aLegacyIdentityWithoutTheFilterKeysDecodes`
- `com.sangwook.ptimer.core.timer.TimerIdentityFilterSummaryTest.aNonArraySummaryDecodesAsEmpty`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.theCapturedSummaryAndReferenceSurviveLaterRenames`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.aStandardOnlyTimerCapturesAStandardOnlySummary`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.aLaterLanguageChangeDoesNotRewriteAnAlreadyCapturedReference`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.aMixedStackRoundTripsThroughExportSession`
- `com.sangwook.ptimer.app.vm.FilterSummaryReferencePresenterTest.groupsItemsBySetWithRepresentationAndMode`
- `com.sangwook.ptimer.app.vm.FilterSummaryReferencePresenterTest.applyFullValueIsNamedAndAStandardZeroIsOmitted`
- `com.sangwook.ptimer.app.vm.FilterSummaryReferencePresenterTest.aStandardOnlyZeroStackHasNoReferenceText`
- `com.sangwook.ptimer.app.vm.FilterSummaryReferencePresenterTest.interleavedSourcesFlushEachGroupInStackOrder`
- `com.sangwook.ptimer.app.vm.FilterSummaryReferencePresenterTest.theSuppliedVocabularyIsTheOneWritten`
- `com.sangwook.ptimer.app.vm.FilterSummaryReferencePresenterTest.missingNamesFallBackToTheSuppliedFallbackTokens`
- `com.sangwook.ptimer.app.ui.timer.TimerFilterReferenceTest.theCapturedStringIsRenderedVerbatim`
- `com.sangwook.ptimer.app.ui.timer.TimerFilterReferenceTest.aRenamedSetDoesNotReachTheCapturedLine`
- `com.sangwook.ptimer.app.ui.timer.TimerFilterReferenceTest.aLegacyPayloadWithoutTheStringStillGetsALine`

### FILTER-PERSIST-004 — Shooting Collection workflow is out of scope

No automated coverage, and none is required: the requirement states the
workflow is outside this capability.

---

## Accessibility and localization

### FILTER-A11Y-001 — one adjustable element per wheel; explicit Plus actions

Partially covered: every wheel is addressed in the instrumented tests by
a single stable label identifying its position and source, and the Plus
control by its single `Add filter` label —

- `com.sangwook.ptimer.app.ui.shooting.FilterStackInteractionTest.addedWheel_appearsInItsSettledSourceGroupWithoutFurtherInteraction`
- `com.sangwook.ptimer.app.ui.shooting.FilterStackInteractionTest.refusedSettle_returnsTheViewportToTheCommittedRow`

Manual only: the adjustable trait, the separation of stable label from
dynamic value, the absence of a repeated label on selection change, and
the Plus control's custom actions (Add, Manage Filter Sets). Verify with
TalkBack on the emulator.

### FILTER-A11Y-002 — color redundant with text; large-text and constrained-height rules

**Manual only.** Verify with TalkBack and at the largest supported text
size on the emulator.

### FILTER-A11Y-003 — equivalent English and Korean terminology

Partially covered at the canonical-token boundary —

- `com.sangwook.ptimer.app.vm.FilterWheelPresenterTest.sourceNameUsesCanonicalEnglish`

Manual only: the actual English/Korean parity of the shipped strings.
Verify by reviewing `values/strings.xml` against `values-ko/strings.xml`.

### FILTER-A11Y-004 — assistive increment/decrement scans past unavailable rows

- `com.sangwook.ptimer.app.vm.FilterWheelAccessibilityAdjustmentTest.skipsUnavailableRowsAndCommitsTheFirstAvailableOne`
- `com.sangwook.ptimer.app.vm.FilterWheelAccessibilityAdjustmentTest.reportsTheNearestRejectionWhenUnavailableRowsBlockTheWholeDirection`
- `com.sangwook.ptimer.app.vm.FilterWheelAccessibilityAdjustmentTest.theEndOfTheWheelIsAPlainBoundaryAndNeverWraps`
- `com.sangwook.ptimer.app.vm.FilterWheelAccessibilityAdjustmentTest.decrementScansBackwardFromTheCurrentRow`
- `com.sangwook.ptimer.app.vm.FilterWheelAccessibilityAdjustmentTest.anUnresolvedCurrentSelectionReportsItsOwnReason`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.anAssistiveAdjustmentSkipsAMountedRowAndCommitsTheNextAvailableOne`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.anAssistiveAdjustmentReportsBoundaryAndUnavailableCorrectly`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.anAssistiveCommitGetsNoSightedFallback`

### FILTER-A11Y-005 — announcement content, ordering, and speech interruption

**Manual only.** The composed spoken value (`filterRowAccessibilityValue`)
has no unit test, and speech interruption and the separately focusable
Total are platform behavior. Verify with TalkBack on the emulator:
adjust a GND wheel and confirm "GND, Apply full value, 3 stops, Total …"
is heard once, and that the Total in the status region is reachable as
its own focus target.

### FILTER-A11Y-006 — frozen order while touch exploration is active, one reconciliation after

- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.suspensionFreezesTheOrderAndResumingReconcilesExactlyOnce`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.resumingWaitsForTouchAndPendingCommitsAndCanBeCancelled`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.launchingWithSuspensionActiveRestoresThePersistedOrder`
- `com.sangwook.ptimer.app.vm.FilterSetControllerTest.anAdditionWhileOrderingIsSuspendedDefersToTheSingleReconciliation` — an explicit addition changes membership without a subtotal-based reorder

Manual only: the platform-capability detection itself
(`TouchExplorationState` observing `AccessibilityManager`, rather than a
named service package). Verify by enabling TalkBack on the emulator.

---

## Contracts with no automated coverage

| Contract | Reason | Verification |
| --- | --- | --- |
| FILTER-CPL-003 | keyboard type is a declaration | emulator: focus a CPL choice field |
| FILTER-CPL-004 | editor copy | read `values/strings.xml` and `values-ko/strings.xml` |
| FILTER-GND-003 | warning copy | emulator: open a GND item's Apply full value |
| FILTER-A11Y-002 | color redundancy and large text | emulator with TalkBack, largest text size |
| FILTER-A11Y-005 | spoken value and speech interruption | emulator with TalkBack |
| FILTER-PERSIST-004 | declared out of scope by the spec | none required |

Requirements with partial coverage — the automated clause is listed
above, the remaining clause is named under its section: FILTER-SET-001
(four-wheel header entry), FILTER-SET-004 (rendered Plus browsing
order), FILTER-SET-005 (color never the sole cue), FILTER-ITEM-007
(session reset), FILTER-GND-002 (Record only as the first-selection
default), FILTER-STACK-005 (reorder animation), FILTER-STACK-006
(announcement wording), FILTER-STACK-007 (rendered visual quietness),
FILTER-STACK-008 (idle summary composition; reclaimed height in the
density tier), FILTER-PLUS-002 (rest-state color cue), FILTER-A11Y-001
(adjustable trait and Plus custom actions), FILTER-A11Y-003 (Korean
parity), FILTER-A11Y-006 (platform capability detection).
